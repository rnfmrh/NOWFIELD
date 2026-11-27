import os
import json
import contextlib
from datetime import datetime, timezone
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Depends, Query, File, Form, UploadFile
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text, inspect
from sqlalchemy.orm import Session

from database import engine, get_db, Base
import models
import schemas
import crud
from kakao_service import kakao_service
from video_service import UPLOAD_DIR, VideoProcessor, MAX_DURATION_SECONDS

SETTINGS_FILE = os.path.join(os.path.dirname(__file__), "admin_settings.json")
DEFAULT_SETTINGS = {
    "angles_radius_km": 1.0,
    "nearby_radius_km": 1.0,
    "nearby_ttl_minutes": 60,
    "feed_ad_interval": 3,
    "web_ad_network": "adfit",
    "adfit_unit_id": "DAN-NOWFIELD01",
    "adsense_client_id": "",
    "adsense_slot_id": "",
}


def _load_settings() -> dict:
    if os.path.exists(SETTINGS_FILE):
        with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
            return {**DEFAULT_SETTINGS, **json.load(f)}
    return dict(DEFAULT_SETTINGS)


def _save_settings(data: dict):
    with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _ensure_db_migrations():
    """
    Ensure existing SQLite/MySQL databases are migrated to the v1.1 CR-01~04 schema:
    - Adds new columns on users & videos if missing
    - Backfills capture_lat/lng, display_lat/lng, published_at, captured_at
    - Drops obsolete license_transactions table (CR-01)
    """
    Base.metadata.create_all(bind=engine)
    inspector = inspect(engine)
    tables = inspector.get_table_names()

    with engine.begin() as conn:
        if "license_transactions" in tables:
            conn.execute(text("DROP TABLE IF EXISTS license_transactions"))

        if "users" in tables:
            user_cols = {c["name"] for c in inspector.get_columns("users")}
            if "exact_location_consent" not in user_cols:
                conn.execute(
                    text("ALTER TABLE users ADD COLUMN exact_location_consent BOOLEAN DEFAULT 0 NOT NULL")
                )
            if "exact_location_consented_at" not in user_cols:
                conn.execute(
                    text("ALTER TABLE users ADD COLUMN exact_location_consented_at DATETIME NULL")
                )

        if "videos" in tables:
            video_cols = {c["name"] for c in inspector.get_columns("videos")}
            additions = [
                ("capture_lat", "FLOAT DEFAULT 37.5204 NOT NULL"),
                ("capture_lng", "FLOAT DEFAULT 127.0229 NOT NULL"),
                ("location_display_mode", "VARCHAR(20) DEFAULT 'exact' NOT NULL"),
                ("display_lat", "FLOAT NULL"),
                ("display_lng", "FLOAT NULL"),
                ("approx_radius_m", "INTEGER DEFAULT 150 NULL"),
                ("accuracy_m", "FLOAT DEFAULT 10.0 NULL"),
                ("support_enabled", "BOOLEAN DEFAULT 0 NOT NULL"),
                ("support_click_count", "INTEGER DEFAULT 0 NOT NULL"),
                ("captured_at", "DATETIME NULL"),
                ("published_at", "DATETIME NULL"),
                ("display_timezone", "VARCHAR(50) DEFAULT 'Asia/Seoul' NOT NULL"),
            ]
            for col_name, col_def in additions:
                if col_name not in video_cols:
                    conn.execute(text(f"ALTER TABLE videos ADD COLUMN {col_name} {col_def}"))

            # CR-01: Remove legacy license_price column if it still exists in DB
            if "license_price" in video_cols:
                try:
                    conn.execute(text("ALTER TABLE videos DROP COLUMN license_price"))
                except Exception:
                    pass

            # CR-02: Allow fuzzed_lat / fuzzed_lng to be NULL when location_display_mode == 'hidden'
            for null_col in ("fuzzed_lat", "fuzzed_lng", "display_lat", "display_lng"):
                if null_col in video_cols:
                    try:
                        conn.execute(text(f"ALTER TABLE videos MODIFY COLUMN {null_col} FLOAT NULL"))
                    except Exception:
                        pass

        # CR-01: Drop legacy licenses table if it still exists in DB
        if "licenses" in tables:
            try:
                conn.execute(text("DROP TABLE licenses"))
            except Exception:
                pass

        if "videos" in tables:

            # Backfill newly added columns from legacy columns where needed
            conn.execute(
                text(
                    "UPDATE videos SET capture_lat = latitude, capture_lng = longitude "
                    "WHERE capture_lat IS NULL OR capture_lat = 37.5204"
                )
            )
            conn.execute(
                text(
                    "UPDATE videos SET display_lat = fuzzed_lat, display_lng = fuzzed_lng "
                    "WHERE display_lat IS NULL AND location_display_mode != 'hidden'"
                )
            )
            conn.execute(
                text("UPDATE videos SET published_at = created_at WHERE published_at IS NULL")
            )
            conn.execute(
                text("UPDATE videos SET captured_at = created_at WHERE captured_at IS NULL")
            )
            conn.execute(
                text(
                    "UPDATE videos SET location_name = '서울 강남구 신사동' "
                    "WHERE location_name LIKE '%,%' OR location_name LIKE '위도%'"
                )
            )


_ensure_db_migrations()


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    _ensure_db_migrations()
    if not os.environ.get("NOWFIELD_NO_SEED"):
        db = next(get_db())
        try:
            await crud.seed_initial_db(db)
        finally:
            db.close()
    yield


app = FastAPI(
    title="NOWFIELD API",
    description="Real-time Field Network Backend v1.1 (CR-01~04 Applied)",
    version="1.5.0",
    lifespan=lifespan,
)

# Enable CORS for Flutter Web & Mobile
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount uploads static directory for streaming videos & thumbnails
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")


# --- Root & Health Check ---

@app.get("/")
def read_root(db: Session = Depends(get_db)):
    user_count = db.query(models.User).count()
    video_count = db.query(models.Video).count()
    return {
        "service": "NOWFIELD API",
        "version": "1.5.0 (v1.1 CR-01~04)",
        "database": "MySQL (nowfield on port 3306)" if "mysql" in str(engine.url) else "SQLite",
        "kakao_integrated": bool(kakao_service.api_key),
        "video_processing": "FFmpeg & FFprobe enabled",
        "user_count": user_count,
        "video_count": video_count,
        "status": "online",
    }


# --- Kakao Local API Endpoints ---

@app.get("/kakao/region")
async def get_kakao_region(
    lat: float = Query(..., description="Latitude"),
    lng: float = Query(..., description="Longitude"),
):
    res = await kakao_service.coord_to_region(lat, lng)
    return res


@app.get("/kakao/search")
async def search_kakao_places(
    query: str = Query(..., description="Place keyword"),
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius: int = 1000,
):
    results = await kakao_service.search_places(query, lat, lng, radius)
    return {"query": query, "count": len(results), "places": results}


@app.get("/search", response_model=schemas.SearchResponse)
async def unified_search(
    q: str = Query("", description="Search keyword (@username, video title, location)"),
    category: Optional[str] = Query(None, description="Optional category filter"),
    db: Session = Depends(get_db),
):
    videos, users = crud.search_videos_and_users(db, q, category)
    places = []
    if q.strip() and not q.strip().startswith("@"):
        try:
            places = await kakao_service.search_places(q.strip(), 37.5250, 127.0250, 5000)
        except Exception:
            places = []
    return schemas.SearchResponse(
        query=q,
        category=category,
        videos=videos,
        users=users,
        places=places[:8],
    )


# --- User & Support Account Endpoints (CR-01 & CR-02) ---

@app.get("/users", response_model=List[schemas.UserResponse])
def list_users(db: Session = Depends(get_db)):
    return crud.get_all_users(db)


@app.post("/users", response_model=schemas.UserResponse)
def create_user(user_in: schemas.UserCreate, db: Session = Depends(get_db)):
    username = user_in.username if user_in.username.startswith("@") else f"@{user_in.username}"
    user_in.username = username
    existing = crud.get_user_by_username(db, username)
    if existing:
        return existing
    return crud.create_user(db, user_in)


@app.get("/users/{user_id}/profile", response_model=schemas.UserProfileSummaryResponse)
def get_user_full_profile(
    user_id: str,
    viewer_id: Optional[str] = Query(None, description="Current logged-in user ID"),
    db: Session = Depends(get_db),
):
    summary = crud.get_user_profile_summary(db, user_id, viewer_id)
    if not summary:
        raise HTTPException(status_code=404, detail="User not found")
    return summary


@app.get("/users/{user_id}/support-account", response_model=Optional[schemas.SupportAccountResponse])
def get_user_support_account(user_id: str, db: Session = Depends(get_db)):
    acc = crud.get_support_account(db, user_id)
    if not acc:
        return None
    return acc


@app.put("/users/{user_id}/support-account", response_model=schemas.SupportAccountResponse)
def update_user_support_account(
    user_id: str,
    payload: schemas.SupportAccountUpsert,
    db: Session = Depends(get_db),
):
    """
    CR-01: Connect & verify external creator support page URL (Ko-fi, Buy Me a Coffee, PayPal.Me).
    NOWFIELD validates the domain allowlist and stores the URL (0% platform fee, no password collected).
    """
    acc, err = crud.upsert_support_account(db, user_id, payload.provider, payload.support_url)
    if err or not acc:
        raise HTTPException(status_code=400, detail=err or "Invalid support URL")
    return acc


@app.delete("/users/{user_id}/support-account")
def disconnect_user_support_account(user_id: str, db: Session = Depends(get_db)):
    """
    CR-01: Disconnect external support account and disable video support buttons.
    """
    ok = crud.disconnect_support_account(db, user_id)
    return {"disconnected": ok, "user_id": user_id}


@app.post("/users/{user_id}/location-consent")
def record_exact_location_consent(
    user_id: str,
    consented: bool = Query(True),
    db: Session = Depends(get_db),
):
    """
    CR-02.B: Record explicit user consent for Exact Location disclosure.
    """
    user = crud.get_user(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.exact_location_consent = consented
    user.exact_location_consented_at = datetime.now(timezone.utc) if consented else None
    db.commit()
    return {
        "user_id": user.id,
        "exact_location_consent": user.exact_location_consent,
        "exact_location_consented_at": user.exact_location_consented_at,
    }


@app.post("/users/{user_id}/follow", response_model=schemas.FollowToggleResponse)
def toggle_follow(
    user_id: str,
    follower_id: str = Query("u_seoul_walker", description="Follower user ID"),
    db: Session = Depends(get_db),
):
    result = crud.toggle_user_follow(db, user_id, follower_id)
    if not result:
        raise HTTPException(status_code=404, detail="Target user not found")
    return result


@app.get("/users/{user_id}/followers")
def get_user_followers(user_id: str, db: Session = Depends(get_db)):
    return crud.get_followers(db, user_id)


@app.get("/users/{user_id}/following")
def get_user_following(user_id: str, db: Session = Depends(get_db)):
    return crud.get_following(db, user_id)


@app.get("/users/{user_id}", response_model=schemas.UserResponse)
def get_user_profile(user_id: str, db: Session = Depends(get_db)):
    user = crud.get_user(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


# --- Video Endpoints ---

@app.post("/videos/upload", response_model=schemas.VideoResponse)
async def upload_video_file(
    video_file: UploadFile = File(..., description="1-minute video file (.mp4, .mov, etc.)"),
    title: str = Form(..., description="Video title (max 100 chars)"),
    subtitle: Optional[str] = Form(None, description="Subtitle or field notes"),
    latitude: float = Form(..., description="Exact capture GPS latitude"),
    longitude: float = Form(..., description="Exact capture GPS longitude"),
    uploader_id: str = Form("u_seoul_walker", description="User ID"),
    location_display_mode: str = Form("exact", description="CR-02: exact, approximate, hidden"),
    exact_location_consented: bool = Form(False, description="CR-02: Explicit consent for exact location"),
    precise_permission_granted: bool = Form(True, description="CR-02: OS precise location permission status"),
    is_sensitive_place: bool = Form(False, description="CR-02: Sensitive place flag"),
    support_enabled: bool = Form(False, description="CR-01: Enable creator support button on this video"),
    captured_at: Optional[str] = Form(None, description="CR-03: Original capture UTC ISO-8601 timestamp"),
    display_timezone: str = Form("Asia/Seoul", description="CR-03: IANA timezone for published_at display"),
    location_name: Optional[str] = Form(None, description="Resolved neighborhood (동) name from client"),
    recorded_duration: Optional[int] = Form(None, description="Client recorded duration in seconds"),
    capture_session_id: Optional[str] = Form(None, description="Capture session identifier"),
    db: Session = Depends(get_db),
):
    """
    Real One-Take Video File Processing (v1.1 CR-01, CR-02, CR-03):
    1. Validates format & file size (max 100MB).
    2. Saves file and computes SHA-256 integrity hash.
    3. Enforces One-Minute Principle (duration <= 60s via ffprobe).
    4. Extracts thumbnail & animated preview.
    5. Reverse-geocodes administrative region via Kakao Local API.
    6. Applies 3-tier Location Privacy (exact / approximate 100~200m / hidden) and separates capture_lat/lng vs display_lat/lng.
    7. Records separate captured_at and published_at (UTC) + display_timezone.
    """
    clean_title = title.strip()[:100]

    # Step 1 Safety Filter: Title & Evasion Pattern Check
    matched_kw = VideoProcessor.check_text_policy_violation(f"{clean_title} {subtitle or ''}")
    if matched_kw:
        raise HTTPException(
            status_code=451,
            detail=f"POLICY_VIOLATION_SEXUAL_CONTENT: Prohibited content detected ({matched_kw}).",
        )

    file_id, raw_path, sha256_hash, file_size = await VideoProcessor.save_raw_video(video_file)

    meta = VideoProcessor.get_video_metadata(raw_path)
    duration = meta.get("duration", 0.0)
    if duration > MAX_DURATION_SECONDS:
        if os.path.exists(raw_path):
            os.remove(raw_path)
        raise HTTPException(
            status_code=400,
            detail=f"영상 길이가 {duration:.1f}초로 60초를 초과했습니다. NOWFIELD는 최대 60초 영상만 허용합니다 (One Minute 원칙).",
        )

    effective_duration = (
        recorded_duration
        if (recorded_duration and 0 < recorded_duration <= 60)
        else int(duration or 15)
    )

    processed_path, video_url = VideoProcessor.transcode_to_faststart(raw_path, file_id)

    # Step 2 Safety Filter: Visual Frame Inspection (FFmpeg keyframes -> NudeNet / YCbCr exposure detector)
    is_frame_safe, frame_violation = VideoProcessor.inspect_video_frames_safety(
        processed_path, file_id, float(effective_duration)
    )
    if not is_frame_safe:
        if os.path.exists(processed_path):
            os.remove(processed_path)
        raise HTTPException(
            status_code=451,
            detail=f"POLICY_VIOLATION_VISUAL_CONTENT: {frame_violation}",
        )

    thumb_url = VideoProcessor.generate_thumbnail(processed_path, file_id)
    preview_url = VideoProcessor.generate_preview_gif(processed_path, file_id)
    audio_url, subtitles_json = VideoProcessor.extract_audio_and_generate_subtitles(
        processed_path, file_id, clean_title, subtitle, float(effective_duration)
    )

    # Step 3 Safety Filter: Transcribed Audio Speech Check
    if subtitles_json:
        speech_violation = VideoProcessor.check_text_policy_violation(subtitles_json)
        if speech_violation:
            for p in (processed_path,):
                if p and os.path.exists(p):
                    os.remove(p)
            raise HTTPException(
                status_code=451,
                detail=f"POLICY_VIOLATION_AUDIO_SPEECH: Prohibited speech detected ({speech_violation}).",
            )

    if location_name and location_name.strip() and not ("," in location_name or location_name.startswith("위도")):
        resolved_location_name = location_name.strip()
    else:
        region_info = await kakao_service.coord_to_region(latitude, longitude)
        resolved_location_name = region_info.get("formatted_name") or crud._normalize_location_dong_name(None, latitude, longitude)

    uploader = crud.get_user(db, uploader_id)
    if not uploader:
        crud.create_user(
            db, schemas.UserCreate(id=uploader_id, username=f"@{uploader_id.replace('u_', '')}")
        )

    parsed_captured_at: Optional[datetime] = None
    if captured_at:
        try:
            norm = captured_at if (captured_at.endswith("Z") or "+" in captured_at) else f"{captured_at}Z"
            parsed_captured_at = datetime.fromisoformat(norm.replace("Z", "+00:00"))
        except Exception:
            parsed_captured_at = None

    video = crud.create_processed_video(
        db=db,
        uploader_id=uploader_id,
        title=clean_title,
        subtitle=subtitle or clean_title,
        video_url=video_url,
        thumbnail_url=thumb_url,
        preview_url=preview_url,
        duration_sec=effective_duration,
        width=meta.get("width"),
        height=meta.get("height"),
        subtitles_json=subtitles_json,
        latitude=latitude,
        longitude=longitude,
        location_name=resolved_location_name,
        original_hash=sha256_hash,
        location_display_mode=location_display_mode,
        exact_location_consented=exact_location_consented,
        precise_permission_granted=precise_permission_granted,
        is_sensitive_place=is_sensitive_place,
        support_enabled=support_enabled,
        captured_at=parsed_captured_at,
        display_timezone=display_timezone or "Asia/Seoul",
        capture_session_id=capture_session_id,
    )

    return crud._to_video_response(video)


@app.post("/videos", response_model=schemas.VideoResponse)
async def upload_video_json(video_in: schemas.VideoCreate, db: Session = Depends(get_db)):
    region_info = await kakao_service.coord_to_region(video_in.latitude, video_in.longitude)
    location_name = region_info.get("formatted_name") or crud._normalize_location_dong_name(None, video_in.latitude, video_in.longitude)

    video = crud.create_video(db, video_in, location_name)
    return crud._to_video_response(video)


@app.patch("/videos/{video_id}/settings", response_model=schemas.VideoResponse)
@app.put("/videos/{video_id}/settings", response_model=schemas.VideoResponse)
async def update_video_settings_endpoint(
    video_id: str,
    payload: schemas.VideoSettingsUpdate,
    db: Session = Depends(get_db),
):
    """
    Spec v1.1 Principle 8 (Privacy by Choice) & CR-01/CR-02:
    Allows creator to change per-video support_enabled and location_display_mode at any time.
    """
    existing = crud.get_video_by_id(db, video_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Video not found")

    resolved_loc_name: Optional[str] = None
    if (
        payload.location_display_mode in ("exact", "approximate")
        and (not existing.location_name or existing.location_name == "위치 미표시")
    ):
        cap_lat = existing.capture_lat if existing.capture_lat is not None else existing.latitude
        cap_lng = existing.capture_lng if existing.capture_lng is not None else existing.longitude
        region_info = await kakao_service.coord_to_region(cap_lat, cap_lng)
        resolved_loc_name = region_info.get("formatted_name") or f"위도 {cap_lat:.3f}"

    updated = crud.update_video_settings(db, video_id, payload, resolved_loc_name)
    if not updated:
        raise HTTPException(status_code=404, detail="Video not found")
    return crud._to_video_response(updated)


@app.post("/videos/{video_id}/support-click", response_model=schemas.SupportClickResponse)
def track_support_click(
    video_id: str,
    viewer_id: Optional[str] = Query(None, description="Viewer user ID"),
    session_id: Optional[str] = Query(None, description="Client session ID"),
    db: Session = Depends(get_db),
):
    """
    CR-01: Track clicks to external creator support URL (logs SupportLinkEvent).
    NOTE: Clicks are recorded for statistical reference only and are NOT treated as completed donations or revenue.
    """
    res = crud.record_support_click(db, video_id, viewer_id=viewer_id, session_id=session_id)
    if not res:
        raise HTTPException(status_code=404, detail="Video not found")
    return res


@app.get("/videos/nearby", response_model=schemas.NearbyResponse)
def get_nearby_videos(
    lat: float = Query(37.5250, description="User current latitude (default: Sinsa/Apgujeong)"),
    lng: float = Query(127.0250, description="User current longitude"),
    radius_km: float = Query(1.0, description="CR-04: Search radius in kilometers (default 1.0km)"),
    time_limit_hours: Optional[float] = Query(
        None, description="CR-04: Pin TTL in hours (defaults to admin setting nearby_ttl_minutes / 60 = 1.0h)"
    ),
    db: Session = Depends(get_db),
):
    """
    CR-04 Nearby Map Pin Lifecycle:
    1. Filters: status == 'public', published_at >= now - TTL (default 60min), distance <= 1km, location_display_mode != 'hidden'
    2. Videos older than TTL are automatically excluded from map pins (while preserved in Home/Profile).
    """
    effective_hours = (
        time_limit_hours
        if (time_limit_hours is not None and time_limit_hours > 0)
        else (_load_settings().get("nearby_ttl_minutes", 60) / 60.0)
    )
    clusters, raw_videos = crud.get_nearby_clusters(db, lat, lng, radius_km, effective_hours)
    return schemas.NearbyResponse(
        center_lat=lat,
        center_lng=lng,
        radius_km=radius_km,
        time_limit_minutes=int(round(effective_hours * 60)),
        total_videos=len(raw_videos),
        clusters=clusters,
        raw_videos=raw_videos,
    )


@app.get("/videos", response_model=List[schemas.VideoResponse])
@app.get("/videos/feed", response_model=List[schemas.VideoResponse])
def get_home_feed(
    limit: int = 15,
    offset: int = 0,
    tab: str = Query("recommended", description="Feed tab: recommended, latest, following"),
    viewer_id: Optional[str] = Query(None, description="Logged-in user ID for following tab"),
    db: Session = Depends(get_db),
):
    return crud.get_feed_videos(db, limit, offset, tab=tab, viewer_id=viewer_id)


@app.get("/videos/{video_id}/angles", response_model=List[schemas.VideoResponse])
def get_video_angles(
    video_id: str,
    radius_km: Optional[float] = Query(None, description="Search radius in km (uses admin setting if omitted)"),
    db: Session = Depends(get_db),
):
    effective_radius = (
        radius_km if radius_km is not None else _load_settings().get("angles_radius_km", 1.0)
    )
    return crud.get_video_angles(db, video_id, effective_radius)


@app.get("/admin/settings")
def get_admin_settings():
    return _load_settings()


@app.put("/admin/settings")
def update_admin_settings(updates: dict):
    settings = _load_settings()
    settings.update(updates)
    _save_settings(settings)
    return settings


@app.delete("/videos/{video_id}")
def delete_video(
    video_id: str,
    requester_id: str = Query("u_seoul_walker", description="ID of the user requesting deletion"),
    db: Session = Depends(get_db),
):
    ok = crud.delete_video(db, video_id, requester_id)
    if not ok:
        raise HTTPException(status_code=403, detail="Video not found or not owned by requester")
    return {"deleted": True, "video_id": video_id}


@app.delete("/users/{user_id}")
def delete_account(user_id: str, db: Session = Depends(get_db)):
    ok = crud.delete_user_account(db, user_id)
    if not ok:
        raise HTTPException(status_code=404, detail="User not found")
    return {"deleted": True, "user_id": user_id}


@app.get("/alerts")
def get_alerts(
    user_id: str = Query("u_seoul_walker", description="Current user ID"),
    db: Session = Depends(get_db),
):
    return {"alerts": crud.get_user_alerts(db, user_id)}


# --- Safety & Moderation Endpoints ---

@app.post("/reports", response_model=schemas.ReportResponse)
def report_video(report_in: schemas.ReportCreate, db: Session = Depends(get_db)):
    video = crud.get_video_by_id(db, report_in.video_id)
    if not video:
        raise HTTPException(status_code=404, detail="Video not found")

    report = crud.create_report(db, report_in)
    return report


# --- Social (Like & Comment) Endpoints ---

@app.post("/videos/{video_id}/like", response_model=schemas.LikeToggleResponse)
def toggle_like(
    video_id: str,
    user_id: str = Query("u_seoul_walker", description="User ID toggling like"),
    db: Session = Depends(get_db),
):
    result = crud.toggle_video_like(db, video_id, user_id)
    if not result:
        raise HTTPException(status_code=404, detail="Video not found")
    return result


@app.get("/videos/{video_id}/comments", response_model=List[schemas.CommentResponse])
def list_comments(video_id: str, db: Session = Depends(get_db)):
    return crud.get_video_comments(db, video_id)


@app.post("/videos/{video_id}/comments", response_model=schemas.CommentResponse)
def add_comment(
    video_id: str,
    comment_in: schemas.CommentCreate,
    db: Session = Depends(get_db),
):
    comment = crud.create_video_comment(db, video_id, comment_in)
    if not comment:
        raise HTTPException(status_code=404, detail="Video not found")
    return comment


# --- Native Feed Ads & Web Ad Network / Creator Pool Revenue Endpoints (Spec v1.1 Section 11 & 13) ---

@app.get("/ads/campaigns", response_model=List[schemas.AdCampaignResponse])
def list_ad_campaigns(db: Session = Depends(get_db)):
    return crud.get_active_ad_campaigns(db)


@app.get("/ads/stats", response_model=schemas.AdRevenueStatsResponse)
def get_ad_stats(db: Session = Depends(get_db)):
    return crud.get_ad_revenue_stats(db, _load_settings())


@app.post("/ads/event", response_model=schemas.AdEventResponse)
def record_ad_event(
    payload: schemas.AdEventCreate,
    db: Session = Depends(get_db),
):
    """
    Record an ad impression or click and accumulate 30% net revenue into the Creator Pool.
    """
    return crud.record_ad_revenue_event(
        db=db,
        ad_id=payload.ad_id,
        event_type=payload.event_type,
        viewer_id=payload.viewer_id,
    )

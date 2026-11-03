import os
import contextlib
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Depends, Query, File, Form, UploadFile
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from database import engine, get_db, Base
import models
import schemas
import crud
from kakao_service import kakao_service, fuzz_coordinates
from video_service import UPLOAD_DIR, VideoProcessor, MAX_DURATION_SECONDS

# Create SQLite database tables if they do not exist
Base.metadata.create_all(bind=engine)

@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Seed initial data into SQLite DB
    db = next(get_db())
    try:
        await crud.seed_initial_db(db)
    finally:
        db.close()
    yield

app = FastAPI(
    title="NOWFIELD API",
    description="Real-time Field Network Backend (SQLite + SQLAlchemy, Kakao Local API & Video Processing)",
    version="1.3.0",
    lifespan=lifespan
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
        "version": "1.4.0",
        "database": "MySQL (nowfield on port 3306)" if "mysql" in str(engine.url) else "SQLite",
        "kakao_integrated": bool(kakao_service.api_key),
        "video_processing": "FFmpeg & FFprobe enabled",
        "user_count": user_count,
        "video_count": video_count,
        "status": "online"
    }

# --- Kakao Local API Endpoints ---

@app.get("/kakao/region")
async def get_kakao_region(lat: float = Query(..., description="Latitude"), lng: float = Query(..., description="Longitude")):
    """
    Direct endpoint to test Kakao Reverse Geocoding.
    """
    res = await kakao_service.coord_to_region(lat, lng)
    return res

@app.get("/kakao/search")
async def search_kakao_places(
    query: str = Query(..., description="Place keyword"),
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius: int = 1000
):
    """
    Search places or landmarks using Kakao Local API.
    """
    results = await kakao_service.search_places(query, lat, lng, radius)
    return {"query": query, "count": len(results), "places": results}

@app.get("/search", response_model=schemas.SearchResponse)
async def unified_search(
    q: str = Query("", description="Search keyword (@username, video title, location)"),
    category: Optional[str] = Query(None, description="Optional category filter"),
    db: Session = Depends(get_db)
):
    """
    Spec #14 Unified Search:
    Searches Username, Video Title, Location, and Category, plus Kakao Local places.
    """
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

# --- User Endpoints ---

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
    db: Session = Depends(get_db)
):
    summary = crud.get_user_profile_summary(db, user_id, viewer_id)
    if not summary:
        raise HTTPException(status_code=404, detail="User not found")
    return summary

@app.post("/users/{user_id}/follow", response_model=schemas.FollowToggleResponse)
def toggle_follow(
    user_id: str,
    follower_id: str = Query("u_seoul_walker", description="Follower user ID"),
    db: Session = Depends(get_db)
):
    result = crud.toggle_user_follow(db, user_id, follower_id)
    if not result:
        raise HTTPException(status_code=404, detail="Target user not found")
    return result

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
    latitude: float = Form(..., description="Exact GPS latitude"),
    longitude: float = Form(..., description="Exact GPS longitude"),
    uploader_id: str = Form("u_seoul_walker", description="User ID"),
    license_enabled: bool = Form(True, description="Whether license sale is enabled"),
    license_price: int = Form(10000, description="Standard license price in KRW"),
    recorded_duration: Optional[int] = Form(None, description="Client recorded duration in seconds"),
    capture_session_id: Optional[str] = Form(None, description="Capture session identifier"),
    db: Session = Depends(get_db)
):
    """
    Real One-Take Video File Processing (One Take & One Minute Principles):
    1. Validates format & file size (max 100MB).
    2. Saves file and computes SHA-256 integrity hash.
    3. Enforces One-Minute Principle (duration <= 60s via ffprobe).
    4. Extracts thumbnail image at 1.0s using ffmpeg.
    5. Reverse-geocodes administrative region via Kakao Local API.
    6. Fuzzes public coordinates (~150m grid) for privacy protection.
    7. Saves into DB and serves via /uploads/videos/{filename}.
    """
    # Enforce 100-char title rule (Spec #3)
    clean_title = title.strip()[:100]

    # Pre-publish safety check for explicit sexual/illegal content (Spec #5.1 & #37)
    banned_keywords = ["성인물", "음란물", "불법촬영", "포르노", "nsfw_ban_test"]
    if any(kw in clean_title.lower() for kw in banned_keywords):
        raise HTTPException(
            status_code=451,
            detail="POLICY_VIOLATION_SEXUAL_CONTENT: This video violates NOWFIELD's Content Policy."
        )

    # 1 & 2. Save raw video and compute SHA-256 integrity hash
    file_id, raw_path, sha256_hash, file_size = await VideoProcessor.save_raw_video(video_file)

    # 3. Extract metadata & verify One Minute Principle via ffprobe
    meta = VideoProcessor.get_video_metadata(raw_path)
    duration = meta.get("duration", 0.0)
    if duration > MAX_DURATION_SECONDS:
        if os.path.exists(raw_path):
            os.remove(raw_path)
        raise HTTPException(
            status_code=400,
            detail=f"영상 길이가 {duration:.1f}초로 60초를 초과했습니다. NOWFIELD는 최대 60초 영상만 허용합니다 (One Minute 원칙)."
        )

    effective_duration = recorded_duration if (recorded_duration and 0 < recorded_duration <= 60) else int(duration or 15)

    # 4. Transcode to Web & Mobile optimized H.264/AAC with +faststart
    processed_path, video_url = VideoProcessor.transcode_to_faststart(raw_path, file_id)

    # 5. Extract keyframe thumbnail at 1.0s
    thumb_url = VideoProcessor.generate_thumbnail(processed_path, file_id)

    # 6. Generate lightweight animated GIF preview for cards & map popups
    preview_url = VideoProcessor.generate_preview_gif(processed_path, file_id)

    # 7. Extract audio & auto-generate timed subtitles (Spec Rule #12)
    audio_url, subtitles_json = VideoProcessor.extract_audio_and_generate_subtitles(
        processed_path, file_id, clean_title, subtitle, float(effective_duration)
    )

    # 8. Fuzz coordinates for privacy protection (Spec Rule #59)
    fuzzed_lat, fuzzed_lng = fuzz_coordinates(latitude, longitude, precision_meters=150.0)

    # 9. Reverse geocoding via Kakao Local API
    region_info = await kakao_service.coord_to_region(latitude, longitude)
    location_name = region_info.get("formatted_name") or f"위도 {latitude:.3f}"

    # Ensure uploader exists
    uploader = crud.get_user(db, uploader_id)
    if not uploader:
        crud.create_user(db, schemas.UserCreate(id=uploader_id, username=f"@{uploader_id.replace('u_', '')}"))

    effective_license_price = license_price if license_enabled else 0

    # 10. Save processed video record into DB
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
        fuzzed_lat=fuzzed_lat,
        fuzzed_lng=fuzzed_lng,
        location_name=location_name,
        original_hash=sha256_hash,
        license_price=effective_license_price
    )

    uploader_name = video.uploader.username if video.uploader else "@anonymous"
    resp = schemas.VideoResponse.model_validate(video)
    resp.uploader_name = uploader_name
    return resp

@app.post("/videos", response_model=schemas.VideoResponse)
async def upload_video_json(video_in: schemas.VideoCreate, db: Session = Depends(get_db)):
    """
    JSON-based video registration (for external URLs or testing).
    """
    fuzzed_lat, fuzzed_lng = fuzz_coordinates(video_in.latitude, video_in.longitude, precision_meters=150.0)
    region_info = await kakao_service.coord_to_region(video_in.latitude, video_in.longitude)
    location_name = region_info.get("formatted_name") or f"위도 {video_in.latitude:.3f}"

    video = crud.create_video(db, video_in, fuzzed_lat, fuzzed_lng, location_name)
    uploader_name = video.uploader.username if video.uploader else "@anonymous"
    resp = schemas.VideoResponse.model_validate(video)
    resp.uploader_name = uploader_name
    return resp

@app.get("/videos/nearby", response_model=schemas.NearbyResponse)
def get_nearby_videos(
    lat: float = Query(37.5250, description="User current latitude (default: Sinsa/Apgujeong)"),
    lng: float = Query(127.0250, description="User current longitude"),
    radius_km: float = Query(3.0, description="Search radius in kilometers"),
    time_limit_hours: float = Query(2.0, description="Time filter in hours"),
    db: Session = Depends(get_db)
):
    """
    Retrieve nearby videos from SQLite DB:
    1. Filters: distance <= radius_km, created_at >= now - time_limit, status == 'public'
    2. Clusters nearby videos within 180m:
       - 1 video: Single Pin
       - 2+ videos: 3-Stack Pin (Multiple Angles)
    """
    clusters, raw_videos = crud.get_nearby_clusters(db, lat, lng, radius_km, time_limit_hours)
    return schemas.NearbyResponse(
        center_lat=lat,
        center_lng=lng,
        radius_km=radius_km,
        total_videos=len(raw_videos),
        clusters=clusters,
        raw_videos=raw_videos
    )

@app.get("/videos/feed", response_model=List[schemas.VideoResponse])
def get_home_feed(
    limit: int = 15,
    offset: int = 0,
    tab: str = Query("recommended", description="Feed tab: recommended, latest, following"),
    viewer_id: Optional[str] = Query(None, description="Logged-in user ID for following tab"),
    db: Session = Depends(get_db)
):
    """
    Home TikTok-style vertical video feed loaded from database.
    Supports Spec #6 tabs: Recommended, Latest, Following.
    """
    return crud.get_feed_videos(db, limit, offset, tab=tab, viewer_id=viewer_id)

@app.delete("/users/{user_id}")
def delete_account(user_id: str, db: Session = Depends(get_db)):
    """
    Spec #1 & #50: General Account Deletion.
    """
    ok = crud.delete_user_account(db, user_id)
    if not ok:
        raise HTTPException(status_code=404, detail="User not found")
    return {"deleted": True, "user_id": user_id}

@app.get("/alerts")
def get_alerts(
    user_id: str = Query("u_seoul_walker", description="Current user ID"),
    db: Session = Depends(get_db)
):
    """
    Spec #16 & #46: Dynamic Alerts feed (Social, Moderation, License, Earnings).
    """
    return {"alerts": crud.get_user_alerts(db, user_id)}

# --- License & Monetization Endpoints ---

@app.post("/videos/{video_id}/license", response_model=schemas.LicenseResponse)
def purchase_license(
    video_id: str,
    buyer_id: str = Query("u_current_buyer", description="ID of purchasing user"),
    db: Session = Depends(get_db)
):
    """
    Purchase video license according to NOWFIELD business model:
    Price: ₩10,000 (Creator 80% = ₩8,000 / Platform 20% = ₩2,000).
    Transaction is saved permanently in SQLite database.
    """
    transaction = crud.create_license_transaction(db, video_id, buyer_id)
    if not transaction:
        raise HTTPException(status_code=404, detail="Video not found")
    return transaction

# --- Safety & Moderation Endpoints ---

@app.post("/reports", response_model=schemas.ReportResponse)
def report_video(report_in: schemas.ReportCreate, db: Session = Depends(get_db)):
    """
    Report inappropriate video (sexual content, violence, privacy violation, etc.).
    Saved in SQLite database for moderation audit.
    """
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
    db: Session = Depends(get_db)
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
    db: Session = Depends(get_db)
):
    comment = crud.create_video_comment(db, video_id, comment_in)
    if not comment:
        raise HTTPException(status_code=404, detail="Video not found")
    return comment

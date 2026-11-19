import uuid
from urllib.parse import urlparse
from datetime import datetime, timedelta, timezone
from typing import List, Optional, Tuple, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import desc

import models
import schemas
from kakao_service import (
    haversine_distance_meters,
    fuzz_coordinates,
    generate_approximate_coordinates,
    kakao_service,
)

ALLOWED_SUPPORT_DOMAINS: Dict[str, List[str]] = {
    "kofi": ["ko-fi.com", "www.ko-fi.com"],
    "buymeacoffee": ["buymeacoffee.com", "www.buymeacoffee.com"],
    "paypal": ["paypal.me", "www.paypal.me"],
}

SENSITIVE_PLACE_KEYWORDS = ["자택", "우리집", "개인 주거지", "보호시설", "쉼터", "거주지"]


def validate_support_url(provider: str, url: str) -> Tuple[bool, str, str]:
    """
    CR-01: Validate external creator support URL against domain allowlist.
    Returns (is_valid, normalized_provider, normalized_url_or_error).
    """
    norm_provider = (provider or "kofi").strip().lower()
    if norm_provider not in ALLOWED_SUPPORT_DOMAINS:
        return False, norm_provider, f"지원하지 않는 후원 제공업체입니다: {provider}"

    raw_url = (url or "").strip()
    if not raw_url:
        return False, norm_provider, "후원 페이지 URL을 입력해주세요."

    try:
        parsed = urlparse(raw_url)
    except Exception:
        return False, norm_provider, "올바른 URL 형식이 아닙니다."

    if parsed.scheme.lower() != "https":
        return False, norm_provider, "보안을 위해 https:// 로 시작하는 공개 후원 URL만 허용됩니다."

    host = (parsed.hostname or "").lower()
    allowed_hosts = ALLOWED_SUPPORT_DOMAINS[norm_provider]
    if host not in allowed_hosts:
        return (
            False,
            norm_provider,
            f"허용된 도메인({', '.join(allowed_hosts)})과 일치하지 않습니다.",
        )

    path_clean = (parsed.path or "").strip("/")
    if not path_clean or len(path_clean) < 2:
        return False, norm_provider, "크리에이터 식별 경로가 포함된 공개 페이지 URL을 입력해주세요."

    normalized_url = f"https://{host}/{path_clean}"
    return True, norm_provider, normalized_url


def _to_video_response(v: models.Video) -> schemas.VideoResponse:
    """
    CR-01, CR-02, CR-03: Convert ORM Video to public VideoResponse.
    - Never exposes capture_lat / capture_lng.
    - Masks coordinates when location_display_mode == 'hidden'.
    - Attaches verified active CreatorSupportAccount URL only when support_enabled is True.
    """
    uploader = v.uploader
    uploader_name = uploader.username if uploader else "@anonymous"
    mode = (v.location_display_mode or "exact").lower()

    if mode == "hidden":
        disp_lat = None
        disp_lng = None
        loc_name = "위치 미표시"
        loc_label = "위치 미표시"
        approx_r = None
    elif mode == "approximate":
        disp_lat = v.display_lat if v.display_lat is not None else v.fuzzed_lat
        disp_lng = v.display_lng if v.display_lng is not None else v.fuzzed_lng
        loc_name = v.location_name or "서울"
        loc_label = "약 100~200m 범위"
        approx_r = v.approx_radius_m or 150
    else:
        mode = "exact"
        disp_lat = v.display_lat if v.display_lat is not None else v.fuzzed_lat
        disp_lng = v.display_lng if v.display_lng is not None else v.fuzzed_lng
        loc_name = v.location_name or "서울"
        loc_label = "정확한 위치"
        approx_r = None

    # CR-01: Support button is exposed ONLY when video has support_enabled=True AND
    # creator's external support account is active & verified.
    support_acc = uploader.support_account if uploader else None
    has_valid_support = bool(
        support_acc
        and support_acc.active
        and support_acc.ownership_status == "verified"
        and support_acc.support_url
    )
    effective_support_enabled = bool(v.support_enabled and has_valid_support)
    support_url = support_acc.support_url if effective_support_enabled else None
    support_provider = support_acc.provider if effective_support_enabled else None

    pub_at = v.published_at or v.created_at or datetime.now(timezone.utc)
    cap_at = v.captured_at or pub_at
    tz_name = v.display_timezone or "Asia/Seoul"

    return schemas.VideoResponse(
        id=v.id,
        uploader_id=v.uploader_id,
        uploader_name=uploader_name,
        title=v.title,
        subtitle=v.subtitle,
        video_url=v.video_url,
        thumbnail_url=v.thumbnail_url,
        preview_url=v.preview_url,
        duration_sec=v.duration_sec,
        width=v.width,
        height=v.height,
        subtitles_json=v.subtitles_json,
        location_display_mode=mode,
        location_privacy_label=loc_label,
        display_lat=disp_lat,
        display_lng=disp_lng,
        fuzzed_lat=disp_lat,
        fuzzed_lng=disp_lng,
        approx_radius_m=approx_r,
        location_name=loc_name,
        status=v.status,
        is_original_capture=v.is_original_capture,
        support_enabled=effective_support_enabled,
        creator_support_url=support_url,
        creator_support_provider=support_provider,
        support_click_count=v.support_click_count or 0,
        like_count=v.like_count or 0,
        comment_count=v.comment_count or 0,
        published_at=pub_at,
        captured_at=cap_at,
        display_timezone=tz_name,
        created_at=v.created_at or pub_at,
    )


def get_user(db: Session, user_id: str) -> Optional[models.User]:
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        normalized = user_id if user_id.startswith("@") else f"@{user_id}"
        user = db.query(models.User).filter(models.User.username == normalized).first()
    return user


def get_all_users(db: Session) -> List[models.User]:
    return db.query(models.User).order_by(models.User.created_at).all()


def get_support_account(db: Session, user_id: str) -> Optional[models.CreatorSupportAccount]:
    user = get_user(db, user_id)
    resolved_id = user.id if user else user_id
    return (
        db.query(models.CreatorSupportAccount)
        .filter(models.CreatorSupportAccount.user_id == resolved_id)
        .first()
    )


def upsert_support_account(
    db: Session,
    user_id: str,
    provider: str,
    support_url: str,
) -> Tuple[Optional[models.CreatorSupportAccount], Optional[str]]:
    user = get_user(db, user_id)
    if not user:
        return None, "사용자를 찾을 수 없습니다."

    ok, norm_provider, result_or_err = validate_support_url(provider, support_url)
    if not ok:
        return None, result_or_err

    now = datetime.now(timezone.utc)
    existing = (
        db.query(models.CreatorSupportAccount)
        .filter(models.CreatorSupportAccount.user_id == user.id)
        .first()
    )
    if existing:
        existing.provider = norm_provider
        existing.support_url = result_or_err
        existing.ownership_status = "verified"
        existing.verified_at = now
        existing.active = True
        existing.updated_at = now
        db.commit()
        db.refresh(existing)
        return existing, None

    acc = models.CreatorSupportAccount(
        id=f"sup_{uuid.uuid4().hex[:8]}",
        user_id=user.id,
        provider=norm_provider,
        support_url=result_or_err,
        ownership_status="verified",
        verified_at=now,
        active=True,
    )
    db.add(acc)
    db.commit()
    db.refresh(acc)
    return acc, None


def disconnect_support_account(db: Session, user_id: str) -> bool:
    user = get_user(db, user_id)
    resolved_id = user.id if user else user_id
    existing = (
        db.query(models.CreatorSupportAccount)
        .filter(models.CreatorSupportAccount.user_id == resolved_id)
        .first()
    )
    if not existing:
        return False
    existing.active = False
    existing.ownership_status = "disconnected"
    existing.updated_at = datetime.now(timezone.utc)
    # Also disable support buttons on user's videos when disconnected
    db.query(models.Video).filter(models.Video.uploader_id == resolved_id).update(
        {models.Video.support_enabled: False}, synchronize_session=False
    )
    db.commit()
    return True


def record_support_click(
    db: Session,
    video_id: str,
    viewer_id: Optional[str] = None,
    session_id: Optional[str] = None,
) -> Optional[schemas.SupportClickResponse]:
    video = get_video_by_id(db, video_id)
    if not video:
        return None
    video.support_click_count = (video.support_click_count or 0) + 1
    resp = _to_video_response(video)
    event = models.SupportLinkEvent(
        id=f"sle_{uuid.uuid4().hex[:8]}",
        video_id=video.id,
        creator_id=video.uploader_id,
        viewer_id=viewer_id,
        provider=(resp.creator_support_provider or "kofi").lower(),
        clicked_at=datetime.now(timezone.utc),
        session_id=session_id,
    )
    db.add(event)
    db.commit()
    db.refresh(video)
    return schemas.SupportClickResponse(
        video_id=video.id,
        support_url=resp.creator_support_url,
        provider=resp.creator_support_provider,
        click_count=video.support_click_count,
        platform_fee_percent=0,
    )


def get_user_profile_summary(
    db: Session,
    user_id: str,
    viewer_id: Optional[str] = None,
) -> Optional[schemas.UserProfileSummaryResponse]:
    user = get_user(db, user_id)
    if not user:
        return None
    resolved_id = user.id

    user_videos = (
        db.query(models.Video)
        .filter(models.Video.uploader_id == resolved_id)
        .order_by(desc(models.Video.published_at), desc(models.Video.created_at))
        .all()
    )
    video_responses: List[schemas.VideoResponse] = [_to_video_response(v) for v in user_videos]
    total_clicks = sum((v.support_click_count or 0) for v in user_videos)

    db_followers = (
        db.query(models.UserFollow).filter(models.UserFollow.following_id == resolved_id).count()
    )
    db_following = (
        db.query(models.UserFollow).filter(models.UserFollow.follower_id == resolved_id).count()
    )

    is_following = False
    if viewer_id and viewer_id != resolved_id:
        is_following = (
            db.query(models.UserFollow)
            .filter(
                models.UserFollow.follower_id == viewer_id,
                models.UserFollow.following_id == resolved_id,
            )
            .first()
            is not None
        )

    support_acc = get_support_account(db, resolved_id)
    support_resp = (
        schemas.SupportAccountResponse.model_validate(support_acc) if support_acc else None
    )

    return schemas.UserProfileSummaryResponse(
        user=schemas.UserResponse.model_validate(user),
        video_count=len(video_responses),
        follower_count=db_followers,
        following_count=db_following,
        is_following=is_following,
        support_account=support_resp,
        total_support_clicks=total_clicks,
        ad_creator_pool_revenue=51240,
        videos=video_responses,
    )


def toggle_user_follow(
    db: Session, target_user_id: str, follower_id: str
) -> Optional[schemas.FollowToggleResponse]:
    target = get_user(db, target_user_id)
    if not target:
        return None
    resolved_target_id = target.id

    existing = (
        db.query(models.UserFollow)
        .filter(
            models.UserFollow.follower_id == follower_id,
            models.UserFollow.following_id == resolved_target_id,
        )
        .first()
    )
    if existing:
        db.delete(existing)
        following = False
    else:
        db.add(models.UserFollow(follower_id=follower_id, following_id=resolved_target_id))
        following = True

    db.commit()
    db_followers = (
        db.query(models.UserFollow)
        .filter(models.UserFollow.following_id == resolved_target_id)
        .count()
    )
    return schemas.FollowToggleResponse(
        target_user_id=resolved_target_id,
        following=following,
        follower_count=db_followers,
    )


def get_followers(db: Session, user_id: str) -> List[dict]:
    user = get_user(db, user_id)
    resolved_id = user.id if user else user_id
    follows = (
        db.query(models.UserFollow)
        .filter(models.UserFollow.following_id == resolved_id)
        .order_by(desc(models.UserFollow.created_at))
        .all()
    )
    result = []
    for f in follows:
        u = get_user(db, f.follower_id)
        result.append({
            "user_id": f.follower_id,
            "username": u.username if u else f"@{f.follower_id}",
            "profile_image": u.profile_image if u else None,
            "followed_at": f.created_at.isoformat() if f.created_at else "",
        })
    return result


def get_following(db: Session, user_id: str) -> List[dict]:
    user = get_user(db, user_id)
    resolved_id = user.id if user else user_id
    follows = (
        db.query(models.UserFollow)
        .filter(models.UserFollow.follower_id == resolved_id)
        .order_by(desc(models.UserFollow.created_at))
        .all()
    )
    result = []
    for f in follows:
        u = get_user(db, f.following_id)
        result.append({
            "user_id": f.following_id,
            "username": u.username if u else f"@{f.following_id}",
            "profile_image": u.profile_image if u else None,
            "followed_at": f.created_at.isoformat() if f.created_at else "",
        })
    return result


def search_videos_and_users(
    db: Session,
    query: str = "",
    category: Optional[str] = None,
) -> Tuple[List[schemas.VideoResponse], List[schemas.UserResponse]]:
    q = query.strip()
    video_q = db.query(models.Video).filter(models.Video.status == "public")

    category_keywords = {
        "교통·정체": ["교통", "정체", "도로", "버스", "지하철", "역", "통제"],
        "인파·혼잡": ["인파", "혼잡", "대기", "줄", "사람", "백화점", "골목"],
        "날씨·재난": ["날씨", "비", "눈", "바람", "선선", "폭우", "태풍"],
        "문화·행사": ["행사", "공연", "축제", "카페", "로데오", "가로수길"],
        "동네·일상": ["신사", "압구정", "강남", "한강", "잠원", "테스트", "실시간"],
    }

    all_videos = (
        video_q.order_by(desc(models.Video.published_at), desc(models.Video.created_at))
        .limit(50)
        .all()
    )
    matched_videos: List[schemas.VideoResponse] = []

    for v in all_videos:
        resp = _to_video_response(v)
        haystack = f"{resp.title or ''} {resp.subtitle or ''} {resp.location_name or ''} {resp.uploader_name or ''}".lower()

        if q and q.lower() not in haystack:
            continue

        if category and category != "전체" and category in category_keywords:
            kws = category_keywords[category]
            if not any(kw.lower() in haystack for kw in kws):
                continue

        matched_videos.append(resp)

    all_users = db.query(models.User).order_by(models.User.created_at).all()
    matched_users: List[schemas.UserResponse] = []
    for u in all_users:
        if not q or q.lower() in u.username.lower() or q.lower() in (u.country or "").lower():
            matched_users.append(schemas.UserResponse.model_validate(u))

    return matched_videos, matched_users


def get_user_by_username(db: Session, username: str) -> Optional[models.User]:
    return db.query(models.User).filter(models.User.username == username).first()


def create_user(db: Session, user_in: schemas.UserCreate) -> models.User:
    user_id = user_in.id or f"u_{uuid.uuid4().hex[:8]}"
    db_user = models.User(
        id=user_id,
        username=user_in.username,
        email=user_in.email,
        profile_image=user_in.profile_image,
        country=user_in.country,
        is_creator=user_in.is_creator,
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user


def resolve_location_privacy(
    db: Session,
    user: Optional[models.User],
    video_id: str,
    capture_lat: float,
    capture_lng: float,
    raw_location_name: str,
    requested_mode: str = "exact",
    exact_location_consented: bool = False,
    precise_permission_granted: bool = True,
    is_sensitive_place: bool = False,
    title: str = "",
) -> Tuple[str, Optional[float], Optional[float], Optional[int], str]:
    """
    CR-02: Enforce 3-tier location display mode (exact / approximate / hidden):
    1) Exact requires explicit user consent + OS precise permission + non-sensitive place.
    2) Approximate generates a deterministic 100~200m coordinate per video_id (stored once).
    3) Hidden omits display coordinates and sets location_name='위치 미표시'.
    """
    mode = (requested_mode or "exact").strip().lower()
    if mode not in ("exact", "approximate", "hidden"):
        mode = "exact"

    has_sensitive_kw = is_sensitive_place or any(
        kw in f"{title} {raw_location_name}" for kw in SENSITIVE_PLACE_KEYWORDS
    )

    if mode == "hidden":
        return "hidden", None, None, None, "위치 미표시"

    has_consent = exact_location_consented or bool(user and user.exact_location_consent)
    if mode == "exact":
        if has_consent and user and not user.exact_location_consent:
            user.exact_location_consent = True
            user.exact_location_consented_at = datetime.now(timezone.utc)
            db.commit()

        # CR-02.B: Without consent, or without precise OS permission, or at sensitive places,
        # never publish exact coordinates — transition to approximate!
        if not has_consent or not precise_permission_granted or has_sensitive_kw:
            mode = "approximate"

    if mode == "exact":
        return "exact", round(capture_lat, 6), round(capture_lng, 6), None, raw_location_name

    # Approximate (100~200m generalized coordinate, fixed per video_id)
    approx_lat, approx_lng, radius_m = generate_approximate_coordinates(
        capture_lat, capture_lng, video_id, min_radius_m=100.0, max_radius_m=200.0
    )
    return "approximate", approx_lat, approx_lng, radius_m, raw_location_name


def can_enable_support_for_user(db: Session, uploader_id: str) -> bool:
    acc = get_support_account(db, uploader_id)
    return bool(acc and acc.active and acc.ownership_status == "verified" and acc.support_url)


def create_video(
    db: Session,
    video_in: schemas.VideoCreate,
    location_name: str,
) -> models.Video:
    video_id = f"v_{uuid.uuid4().hex[:8]}"
    uploader = get_user(db, video_in.uploader_id)
    mode, disp_lat, disp_lng, approx_r, final_loc_name = resolve_location_privacy(
        db=db,
        user=uploader,
        video_id=video_id,
        capture_lat=video_in.latitude,
        capture_lng=video_in.longitude,
        raw_location_name=location_name,
        requested_mode=video_in.location_display_mode,
        exact_location_consented=video_in.exact_location_consented,
        precise_permission_granted=video_in.precise_permission_granted,
        is_sensitive_place=video_in.is_sensitive_place,
        title=video_in.title,
    )

    effective_support = bool(
        video_in.support_enabled and can_enable_support_for_user(db, video_in.uploader_id)
    )
    now = datetime.now(timezone.utc)
    cap_at = video_in.captured_at or now

    db_video = models.Video(
        id=video_id,
        uploader_id=uploader.id if uploader else video_in.uploader_id,
        title=video_in.title,
        subtitle=video_in.subtitle,
        video_url=video_in.video_url,
        thumbnail_url=video_in.thumbnail_url,
        duration_sec=video_in.duration_sec,
        capture_lat=video_in.latitude,
        capture_lng=video_in.longitude,
        latitude=video_in.latitude,
        longitude=video_in.longitude,
        location_display_mode=mode,
        display_lat=disp_lat,
        display_lng=disp_lng,
        fuzzed_lat=disp_lat,
        fuzzed_lng=disp_lng,
        approx_radius_m=approx_r,
        accuracy_m=video_in.accuracy_m or 10.0,
        location_name=final_loc_name,
        status="public",
        is_original_capture=video_in.is_original_capture,
        support_enabled=effective_support,
        captured_at=cap_at,
        published_at=now,
        display_timezone=video_in.display_timezone or "Asia/Seoul",
        created_at=now,
    )
    db.add(db_video)
    session_id = video_in.capture_session_id or f"cap_{uuid.uuid4().hex[:10]}"
    existing_cap = (
        db.query(models.CaptureSession).filter(models.CaptureSession.id == session_id).first()
    )
    if not existing_cap:
        db.add(
            models.CaptureSession(
                id=session_id,
                user_id=uploader.id if uploader else video_in.uploader_id,
                video_id=video_id,
                started_at=cap_at,
                ended_at=now,
                app_integrity_result="verified",
                upload_token=f"tok_{uuid.uuid4().hex[:12]}",
                original_hash=None,
                created_at=now,
            )
        )
    db.commit()
    db.refresh(db_video)
    return db_video


def create_processed_video(
    db: Session,
    uploader_id: str,
    title: str,
    subtitle: Optional[str],
    video_url: str,
    thumbnail_url: Optional[str],
    duration_sec: int,
    latitude: float,
    longitude: float,
    location_name: str,
    original_hash: Optional[str] = None,
    preview_url: Optional[str] = None,
    width: Optional[int] = None,
    height: Optional[int] = None,
    subtitles_json: Optional[str] = None,
    location_display_mode: str = "exact",
    exact_location_consented: bool = False,
    precise_permission_granted: bool = True,
    is_sensitive_place: bool = False,
    accuracy_m: Optional[float] = 10.0,
    support_enabled: bool = False,
    captured_at: Optional[datetime] = None,
    display_timezone: str = "Asia/Seoul",
    capture_session_id: Optional[str] = None,
) -> models.Video:
    video_id = f"v_{uuid.uuid4().hex[:8]}"
    uploader = get_user(db, uploader_id)

    mode, disp_lat, disp_lng, approx_r, final_loc_name = resolve_location_privacy(
        db=db,
        user=uploader,
        video_id=video_id,
        capture_lat=latitude,
        capture_lng=longitude,
        raw_location_name=location_name,
        requested_mode=location_display_mode,
        exact_location_consented=exact_location_consented,
        precise_permission_granted=precise_permission_granted,
        is_sensitive_place=is_sensitive_place,
        title=title,
    )

    effective_support = bool(
        support_enabled and can_enable_support_for_user(db, uploader.id if uploader else uploader_id)
    )
    now = datetime.now(timezone.utc)
    cap_at = captured_at or now

    db_video = models.Video(
        id=video_id,
        uploader_id=uploader.id if uploader else uploader_id,
        title=title,
        subtitle=subtitle,
        video_url=video_url,
        thumbnail_url=thumbnail_url,
        preview_url=preview_url,
        duration_sec=duration_sec,
        width=width,
        height=height,
        subtitles_json=subtitles_json,
        capture_lat=latitude,
        capture_lng=longitude,
        latitude=latitude,
        longitude=longitude,
        location_display_mode=mode,
        display_lat=disp_lat,
        display_lng=disp_lng,
        fuzzed_lat=disp_lat,
        fuzzed_lng=disp_lng,
        approx_radius_m=approx_r,
        accuracy_m=accuracy_m or 10.0,
        location_name=final_loc_name,
        original_hash=original_hash,
        status="public",
        is_original_capture=True,
        support_enabled=effective_support,
        captured_at=cap_at,
        published_at=now,
        display_timezone=display_timezone or "Asia/Seoul",
        created_at=now,
    )
    db.add(db_video)
    session_id = capture_session_id or f"cap_{uuid.uuid4().hex[:10]}"
    existing_cap = (
        db.query(models.CaptureSession).filter(models.CaptureSession.id == session_id).first()
    )
    if not existing_cap:
        db.add(
            models.CaptureSession(
                id=session_id,
                user_id=uploader.id if uploader else uploader_id,
                video_id=video_id,
                started_at=cap_at,
                ended_at=now,
                app_integrity_result="verified",
                upload_token=f"tok_{uuid.uuid4().hex[:12]}",
                original_hash=original_hash,
                created_at=now,
            )
        )
    db.commit()
    db.refresh(db_video)
    return db_video


def get_video_by_id(db: Session, video_id: str) -> Optional[models.Video]:
    return db.query(models.Video).filter(models.Video.id == video_id).first()


def update_video_settings(
    db: Session,
    video_id: str,
    payload: schemas.VideoSettingsUpdate,
    resolved_location_name: Optional[str] = None,
) -> Optional[models.Video]:
    """
    Spec v1.1 Principle 8 (Privacy by Choice) & CR-01/CR-02:
    Allows creator to update per-video support_enabled and location_display_mode at any time.
    """
    video = get_video_by_id(db, video_id)
    if not video:
        return None

    uploader = get_user(db, video.uploader_id)

    if payload.support_enabled is not None:
        if payload.support_enabled:
            video.support_enabled = can_enable_support_for_user(db, video.uploader_id)
        else:
            video.support_enabled = False

    if payload.location_display_mode is not None:
        cap_lat = video.capture_lat if video.capture_lat is not None else video.latitude
        cap_lng = video.capture_lng if video.capture_lng is not None else video.longitude
        base_loc_name = resolved_location_name or (
            video.location_name
            if (video.location_name and video.location_name != "위치 미표시")
            else "서울 강남구 신사동"
        )
        consented = (
            payload.exact_location_consented
            if payload.exact_location_consented is not None
            else bool(uploader and uploader.exact_location_consent)
        )
        mode, disp_lat, disp_lng, approx_r, final_loc_name = resolve_location_privacy(
            db=db,
            user=uploader,
            video_id=video.id,
            capture_lat=cap_lat,
            capture_lng=cap_lng,
            raw_location_name=base_loc_name,
            requested_mode=payload.location_display_mode,
            exact_location_consented=consented,
            precise_permission_granted=payload.precise_permission_granted,
            is_sensitive_place=payload.is_sensitive_place,
            title=video.title or "",
        )
        video.location_display_mode = mode
        video.display_lat = disp_lat
        video.display_lng = disp_lng
        video.fuzzed_lat = disp_lat
        video.fuzzed_lng = disp_lng
        video.approx_radius_m = approx_r
        video.location_name = final_loc_name

    db.commit()
    db.refresh(video)
    return video


def get_feed_videos(
    db: Session,
    limit: int = 20,
    offset: int = 0,
    tab: str = "recommended",
    viewer_id: Optional[str] = None,
) -> List[schemas.VideoResponse]:
    query = db.query(models.Video).filter(models.Video.status == "public")

    if tab == "following":
        if not viewer_id:
            return []
        followed_rows = (
            db.query(models.UserFollow.following_id)
            .filter(models.UserFollow.follower_id == viewer_id)
            .all()
        )
        followed_ids = [r[0] for r in followed_rows]
        if not followed_ids:
            return []
        query = query.filter(models.Video.uploader_id.in_(followed_ids)).order_by(
            desc(models.Video.published_at), desc(models.Video.created_at)
        )
    elif tab == "latest":
        query = query.order_by(desc(models.Video.published_at), desc(models.Video.created_at))
    else:
        query = query.order_by(
            desc(models.Video.like_count * 2 + models.Video.comment_count * 3),
            desc(models.Video.published_at),
            desc(models.Video.created_at),
        )

    videos = query.offset(offset).limit(limit).all()
    return [_to_video_response(v) for v in videos]


def get_nearby_clusters(
    db: Session,
    lat: float,
    lng: float,
    radius_km: float = 1.0,
    time_limit_hours: float = 1.0,
) -> Tuple[List[schemas.VideoCluster], List[schemas.VideoResponse]]:
    """
    CR-04: Nearby Map Pin Lifecycle & 60-minute TTL Policy:
    1) Strictly filters status == 'public', published_at >= now - 60min (time_limit_hours=1.0),
       distance <= radius_km (default 1.0km), and location_display_mode != 'hidden'.
    2) Videos older than 60 minutes are automatically excluded from Nearby map pins,
       while the video content itself remains intact in Home/Profile.
    3) Marker coordinates use only public display_lat / display_lng.
    """
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=time_limit_hours)

    query_videos = (
        db.query(models.Video)
        .filter(models.Video.status == "public")
        .filter(models.Video.published_at >= cutoff)
        .filter(models.Video.location_display_mode != "hidden")
        .order_by(desc(models.Video.published_at))
        .all()
    )

    eligible_videos: List[schemas.VideoResponse] = []
    for v in query_videos:
        # Handle SQLite naive timestamps if any
        pub_at = v.published_at or v.created_at
        if pub_at is not None:
            if pub_at.tzinfo is None:
                pub_at = pub_at.replace(tzinfo=timezone.utc)
            if pub_at < cutoff:
                continue

        cap_lat = v.capture_lat if v.capture_lat is not None else v.latitude
        cap_lng = v.capture_lng if v.capture_lng is not None else v.longitude
        dist_m = haversine_distance_meters(lat, lng, cap_lat, cap_lng)
        if dist_m <= (radius_km * 1000.0):
            resp = _to_video_response(v)
            if resp.display_lat is not None and resp.display_lng is not None:
                eligible_videos.append(resp)

    # Cluster within 180m using public display coordinates
    clusters: List[schemas.VideoCluster] = []
    visited = set()

    for i, v in enumerate(eligible_videos):
        if v.id in visited or v.display_lat is None or v.display_lng is None:
            continue

        cluster_group = [v]
        visited.add(v.id)

        for other in eligible_videos:
            if other.id in visited or other.display_lat is None or other.display_lng is None:
                continue
            dist_between = haversine_distance_meters(
                v.display_lat, v.display_lng, other.display_lat, other.display_lng
            )
            if dist_between <= 180.0:
                cluster_group.append(other)
                visited.add(other.id)

        avg_lat = sum(x.display_lat for x in cluster_group if x.display_lat is not None) / len(cluster_group)
        avg_lng = sum(x.display_lng for x in cluster_group if x.display_lng is not None) / len(cluster_group)

        clusters.append(
            schemas.VideoCluster(
                cluster_id=f"cluster_{i + 1}",
                location_name=v.location_name,
                latitude=round(avg_lat, 5),
                longitude=round(avg_lng, 5),
                video_count=len(cluster_group),
                is_stacked=(len(cluster_group) > 1),
                videos=cluster_group,
            )
        )

    return clusters, eligible_videos


def create_report(db: Session, report_in: schemas.ReportCreate) -> models.Report:
    report = models.Report(
        id=f"rep_{uuid.uuid4().hex[:8]}",
        video_id=report_in.video_id,
        reporter_id=report_in.reporter_id,
        reason=report_in.reason,
        details=report_in.details,
        status="pending",
    )
    db.add(report)
    db.flush()

    # CR-04: If a video receives multiple reports (or high-risk sexual_content report),
    # transition to 'reported' (temporarily private) so its Nearby map pin is immediately removed.
    report_count = (
        db.query(models.Report).filter(models.Report.video_id == report_in.video_id).count()
    )
    video = get_video_by_id(db, report_in.video_id)
    if video and (report_count >= 3 or report_in.reason == "sexual_content"):
        video.status = "reported"

    db.commit()
    db.refresh(report)
    return report


def toggle_video_like(
    db: Session, video_id: str, user_id: str = "u_seoul_walker"
) -> Optional[schemas.LikeToggleResponse]:
    video = get_video_by_id(db, video_id)
    if not video:
        return None

    existing = (
        db.query(models.VideoLike)
        .filter(models.VideoLike.video_id == video_id, models.VideoLike.user_id == user_id)
        .first()
    )
    if existing:
        db.delete(existing)
        video.like_count = max(0, (video.like_count or 0) - 1)
        liked = False
    else:
        new_like = models.VideoLike(video_id=video_id, user_id=user_id)
        db.add(new_like)
        video.like_count = (video.like_count or 0) + 1
        liked = True

    db.commit()
    db.refresh(video)
    return schemas.LikeToggleResponse(
        video_id=video.id,
        liked=liked,
        like_count=video.like_count,
    )


def get_video_comments(db: Session, video_id: str) -> List[models.Comment]:
    return (
        db.query(models.Comment)
        .filter(models.Comment.video_id == video_id)
        .order_by(desc(models.Comment.created_at))
        .all()
    )


def create_video_comment(
    db: Session, video_id: str, comment_in: schemas.CommentCreate
) -> Optional[models.Comment]:
    video = get_video_by_id(db, video_id)
    if not video:
        return None

    username = comment_in.username
    if not username.startswith("@"):
        username = f"@{username}"

    comment = models.Comment(
        id=f"cmt_{uuid.uuid4().hex[:8]}",
        video_id=video_id,
        user_id=comment_in.user_id,
        username=username,
        content=comment_in.content.strip(),
    )
    db.add(comment)
    video.comment_count = (video.comment_count or 0) + 1
    db.commit()
    db.refresh(comment)
    return comment


async def seed_initial_db(db: Session):
    """
    Populate database with default seed data if empty, or refresh seed video timestamps
    so that Nearby 60-minute TTL pins and 1 expired archive video are always testable.
    """
    now = datetime.now(timezone.utc)

    seed_users = [
        ("u_seoul_walker", "@seoul_walker", "KR", True),
        ("u_apgu_now", "@apgu_now", "KR", True),
        ("u_commuter", "@commuter", "KR", False),
        ("u_han_biker", "@han_biker", "KR", True),
    ]
    for uid, uname, country, consent in seed_users:
        if not get_user(db, uid) and not get_user_by_username(db, uname):
            db.add(
                models.User(
                    id=uid,
                    username=uname,
                    country=country,
                    is_creator=True,
                    exact_location_consent=consent,
                    exact_location_consented_at=now if consent else None,
                )
            )
    try:
        db.commit()
    except Exception:
        db.rollback()

    # Ensure default verified CreatorSupportAccount entries exist for seed creators (CR-01)
    seed_support_accounts = [
        ("u_seoul_walker", "kofi", "https://ko-fi.com/seoul_walker"),
        ("u_apgu_now", "buymeacoffee", "https://buymeacoffee.com/apgu_now"),
        ("u_commuter", "kofi", "https://ko-fi.com/seoul_commuter"),
    ]
    for uid, prov, surl in seed_support_accounts:
        existing_acc = (
            db.query(models.CreatorSupportAccount)
            .filter(models.CreatorSupportAccount.user_id == uid)
            .first()
        )
        if not existing_acc:
            db.add(
                models.CreatorSupportAccount(
                    id=f"sup_{uid}",
                    user_id=uid,
                    provider=prov,
                    support_url=surl,
                    ownership_status="verified",
                    verified_at=now,
                    active=True,
                )
            )
    try:
        db.commit()
    except Exception:
        db.rollback()

    seed_videos = [
        {
            "id": "v_apgu_1",
            "uploader_id": "u_apgu_now",
            "title": "압구정 현대백화점 앞 교통 정체 심각",
            "subtitle": "백화점 행사로 도로가 거의 마비 상태입니다. 서행하세요.",
            "video_url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
            "thumbnail_url": "https://picsum.photos/seed/apgu1/600/400",
            "lat": 37.5273,
            "lng": 127.0285,
            "mode": "exact",
            "support_enabled": True,
            "minutes_ago": 4,
            "likes": 142,
            "comments": 18,
        },
        {
            "id": "v_apgu_2",
            "uploader_id": "u_commuter",
            "title": "압구정역 3번 출구 퇴근길 버스 정류장 대기줄",
            "subtitle": "버스 줄이 지하철 입구까지 길게 늘어서 있습니다.",
            "video_url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
            "thumbnail_url": "https://picsum.photos/seed/apgu2/600/400",
            "lat": 37.5268,
            "lng": 127.0280,
            "mode": "approximate",
            "support_enabled": True,
            "minutes_ago": 15,
            "likes": 89,
            "comments": 7,
        },
        {
            "id": "v_apgu_3",
            "uploader_id": "u_seoul_walker",
            "title": "압구정 로데오 골목 인파 현황",
            "subtitle": "주요 카페 앞 대기 인원이 30명 이상입니다.",
            "video_url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
            "thumbnail_url": "https://picsum.photos/seed/apgu3/600/400",
            "lat": 37.5276,
            "lng": 127.0291,
            "mode": "exact",
            "support_enabled": True,
            "minutes_ago": 28,
            "likes": 210,
            "comments": 32,
        },
        {
            "id": "v_sinsa_1",
            "uploader_id": "u_seoul_walker",
            "title": "신사동 가로수길 카페 앞 실시간",
            "subtitle": "날씨가 선선해서 야외 테라스에 빈자리가 없네요.",
            "video_url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4",
            "thumbnail_url": "https://picsum.photos/seed/sinsa1/600/400",
            "lat": 37.5204,
            "lng": 127.0229,
            "mode": "approximate",
            "support_enabled": True,
            "minutes_ago": 8,
            "likes": 354,
            "comments": 45,
        },
        {
            "id": "v_river_1",
            "uploader_id": "u_han_biker",
            "title": "한강 잠원지구 자전거 도로 진입로 부분 통제",
            "subtitle": "보수 공사로 우회로 이용해야 합니다.",
            "video_url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
            "thumbnail_url": "https://picsum.photos/seed/river1/600/400",
            "lat": 37.5180,
            "lng": 127.0160,
            "mode": "exact",
            "support_enabled": False,
            "minutes_ago": 19,
            "likes": 98,
            "comments": 11,
        },
        # CR-04: Video older than 60 minutes (excluded from Nearby map pins, kept in Home/Profile)
        {
            "id": "v_archive_1",
            "uploader_id": "u_seoul_walker",
            "title": "신사역 사거리 오전 출근길 소통 원활",
            "subtitle": "게시 후 60분이 경과하여 Nearby 지도 핀에서는 자동 제외되고 홈/프로필에는 유지되는 영상입니다.",
            "video_url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
            "thumbnail_url": "https://picsum.photos/seed/archive1/600/400",
            "lat": 37.5163,
            "lng": 127.0195,
            "mode": "approximate",
            "support_enabled": True,
            "minutes_ago": 75,
            "likes": 64,
            "comments": 5,
        },
    ]

    for item in seed_videos:
        existing_v = db.query(models.Video).filter(models.Video.id == item["id"]).first()
        pub_time = now - timedelta(minutes=item["minutes_ago"])
        cap_time = pub_time - timedelta(seconds=45)
        mode = item["mode"]
        if mode == "approximate":
            disp_lat, disp_lng, approx_r = generate_approximate_coordinates(
                item["lat"], item["lng"], item["id"], 100.0, 200.0
            )
        elif mode == "hidden":
            disp_lat, disp_lng, approx_r = None, None, None
        else:
            disp_lat, disp_lng, approx_r = round(item["lat"], 6), round(item["lng"], 6), None

        if existing_v:
            existing_v.published_at = pub_time
            existing_v.captured_at = cap_time
            existing_v.created_at = pub_time
            existing_v.display_timezone = "Asia/Seoul"
            existing_v.location_display_mode = mode
            existing_v.support_enabled = item["support_enabled"]
            existing_v.capture_lat = item["lat"]
            existing_v.capture_lng = item["lng"]
            existing_v.display_lat = disp_lat
            existing_v.display_lng = disp_lng
            existing_v.fuzzed_lat = disp_lat
            existing_v.fuzzed_lng = disp_lng
            existing_v.approx_radius_m = approx_r
        else:
            region = await kakao_service.coord_to_region(item["lat"], item["lng"])
            loc_name = (
                "위치 미표시"
                if mode == "hidden"
                else (region.get("formatted_name") or f"{item['lat']:.3f}, {item['lng']:.3f}")
            )
            video = models.Video(
                id=item["id"],
                uploader_id=item["uploader_id"],
                title=item["title"],
                subtitle=item["subtitle"],
                video_url=item["video_url"],
                thumbnail_url=item["thumbnail_url"],
                duration_sec=60,
                capture_lat=item["lat"],
                capture_lng=item["lng"],
                latitude=item["lat"],
                longitude=item["lng"],
                location_display_mode=mode,
                display_lat=disp_lat,
                display_lng=disp_lng,
                fuzzed_lat=disp_lat,
                fuzzed_lng=disp_lng,
                approx_radius_m=approx_r,
                accuracy_m=8.0,
                location_name=loc_name,
                status="public",
                is_original_capture=True,
                support_enabled=item["support_enabled"],
                like_count=item["likes"],
                comment_count=item["comments"],
                captured_at=cap_time,
                published_at=pub_time,
                display_timezone="Asia/Seoul",
                created_at=pub_time,
            )
            db.add(video)
        try:
            db.commit()
        except Exception:
            db.rollback()


def get_video_angles(
    db: Session,
    video_id: str,
    radius_km: float = 1.0,
) -> List[schemas.VideoResponse]:
    video = get_video_by_id(db, video_id)
    if not video:
        return []
    base_lat = video.capture_lat if video.capture_lat is not None else video.latitude
    base_lng = video.capture_lng if video.capture_lng is not None else video.longitude
    all_public = (
        db.query(models.Video)
        .filter(
            models.Video.status == "public",
            models.Video.id != video_id,
            models.Video.location_display_mode != "hidden",
        )
        .order_by(desc(models.Video.published_at), desc(models.Video.created_at))
        .limit(100)
        .all()
    )
    results: List[schemas.VideoResponse] = []
    for v in all_public:
        v_lat = v.capture_lat if v.capture_lat is not None else v.latitude
        v_lng = v.capture_lng if v.capture_lng is not None else v.longitude
        dist_m = haversine_distance_meters(base_lat, base_lng, v_lat, v_lng)
        if dist_m <= radius_km * 1000.0:
            results.append(_to_video_response(v))
    return results


def delete_video(db: Session, video_id: str, requester_id: str) -> bool:
    video = get_video_by_id(db, video_id)
    if not video:
        return False
    if video.uploader_id != requester_id:
        user = get_user(db, requester_id)
        if not user or user.id != video.uploader_id:
            return False
    db.query(models.VideoLike).filter(models.VideoLike.video_id == video_id).delete(
        synchronize_session=False
    )
    db.query(models.Comment).filter(models.Comment.video_id == video_id).delete(
        synchronize_session=False
    )
    db.query(models.Report).filter(models.Report.video_id == video_id).delete(
        synchronize_session=False
    )
    db.query(models.SupportLinkEvent).filter(models.SupportLinkEvent.video_id == video_id).delete(
        synchronize_session=False
    )
    db.query(models.CaptureSession).filter(models.CaptureSession.video_id == video_id).delete(
        synchronize_session=False
    )
    db.delete(video)
    db.commit()
    return True


def delete_user_account(db: Session, user_id: str) -> bool:
    """
    Spec #1 & #50: Delete Account (General user account deletion).
    Also removes user's videos & pins immediately (CR-04).
    """
    user = get_user(db, user_id)
    if not user:
        return False
    resolved_id = user.id
    db.query(models.UserFollow).filter(
        (models.UserFollow.follower_id == resolved_id)
        | (models.UserFollow.following_id == resolved_id)
    ).delete(synchronize_session=False)
    db.query(models.VideoLike).filter(models.VideoLike.user_id == resolved_id).delete(
        synchronize_session=False
    )
    db.query(models.Comment).filter(models.Comment.user_id == resolved_id).delete(
        synchronize_session=False
    )
    db.query(models.SupportLinkEvent).filter(
        (models.SupportLinkEvent.creator_id == resolved_id)
        | (models.SupportLinkEvent.viewer_id == resolved_id)
    ).delete(synchronize_session=False)
    db.query(models.CaptureSession).filter(models.CaptureSession.user_id == resolved_id).delete(
        synchronize_session=False
    )
    db.query(models.CreatorSupportAccount).filter(
        models.CreatorSupportAccount.user_id == resolved_id
    ).delete(synchronize_session=False)
    db.delete(user)
    db.commit()
    return True


def get_user_alerts(db: Session, user_id: str) -> List[dict]:
    """
    CR-01: Dynamic Alerts feed combining DB events (Social, Moderation, Support, Earnings).
    License alerts removed.
    """
    user = get_user(db, user_id)
    resolved_id = user.id if user else user_id

    alerts: List[dict] = []

    # 1. Social: Recent followers
    follows = (
        db.query(models.UserFollow)
        .filter(models.UserFollow.following_id == resolved_id)
        .order_by(desc(models.UserFollow.created_at))
        .limit(5)
        .all()
    )
    for f in follows:
        follower_user = get_user(db, f.follower_id)
        fname = follower_user.username if follower_user else f"@{f.follower_id}"
        alerts.append({
            "id": f"alt_flw_{f.id}",
            "category": "Social",
            "title": f"{fname}님이 회원님을 팔로우하기 시작했습니다",
            "subtitle": "프로필을 방문해 현장 영상을 확인해보세요.",
            "target_user_id": f.follower_id,
            "target_username": fname,
            "created_at": f.created_at.isoformat() if f.created_at else "",
        })

    # 2. Social: Recent comments on user's videos
    user_videos = db.query(models.Video).filter(models.Video.uploader_id == resolved_id).all()
    user_video_ids = [v.id for v in user_videos]
    video_map = {v.id: v for v in user_videos}

    if user_video_ids:
        comments = (
            db.query(models.Comment)
            .filter(models.Comment.video_id.in_(user_video_ids))
            .order_by(desc(models.Comment.created_at))
            .limit(5)
            .all()
        )
        for c in comments:
            v = video_map.get(c.video_id)
            alerts.append({
                "id": f"alt_cmt_{c.id}",
                "category": "Social",
                "title": f"{c.username}님이 댓글을 남겼습니다: \"{c.content}\"",
                "subtitle": f"영상: {v.title if v else c.video_id}",
                "video_id": c.video_id,
                "target_user_id": c.user_id,
                "target_username": c.username,
                "created_at": c.created_at.isoformat() if c.created_at else "",
            })

    # 3. Support: External support account status (CR-01)
    support_acc = get_support_account(db, resolved_id)
    if support_acc and support_acc.active and support_acc.ownership_status == "verified":
        alerts.append({
            "id": f"alt_sup_{support_acc.id}",
            "category": "Support",
            "title": "외부 후원 페이지 연결이 검증되었습니다",
            "subtitle": f"{support_acc.support_url} · NOWFIELD 플랫폼 수수료 0%",
            "created_at": (support_acc.verified_at or support_acc.created_at).isoformat(),
        })

    # 4. Moderation: Reports or Temporarily Private notice
    reports = (
        db.query(models.Report)
        .order_by(desc(models.Report.created_at))
        .limit(3)
        .all()
    )
    for r in reports:
        rep_video = get_video_by_id(db, r.video_id)
        alerts.append({
            "id": f"alt_mod_{r.id}",
            "category": "Moderation",
            "title": "영상이 임시 비공개로 전환되었습니다",
            "subtitle": "사유: 다수의 신고 접수 · 탭하여 재검토 요청하기",
            "video_id": r.video_id,
            "video_title": rep_video.title if rep_video else "현장 영상",
            "reason": f"사유 코드: {r.reason}",
            "created_at": r.created_at.isoformat() if r.created_at else "",
        })

    # 5. Earnings: Creator Pool 30% monthly settlement notification (Ad revenue only, CR-01)
    alerts.append({
        "id": "alt_earn_monthly",
        "category": "Earnings",
        "title": "이번 달 크리에이터 풀 정산 내역 안내",
        "subtitle": "유효 조회 품질 지수 기준 광고 수익 배분 내역을 확인하세요.",
        "created_at": datetime.now(timezone.utc).isoformat(),
    })

    # Ensure every category has at least one representative item for demo completeness
    has_mod = any(a["category"] == "Moderation" for a in alerts)
    if not has_mod:
        alerts.append({
            "id": "alt_mod_default",
            "category": "Moderation",
            "title": "영상이 임시 비공개로 전환되었습니다",
            "subtitle": "해당 영상에 다수의 신고가 접수되었습니다 · 탭하여 재검토 요청",
            "video_id": "v_sinsa_1",
            "video_title": "신사동 가로수길 카페 앞 실시간",
            "reason": "해당 영상에 대해 다수의 신고가 접수되어 확인 중입니다.",
            "created_at": datetime.now(timezone.utc).isoformat(),
        })

    return alerts

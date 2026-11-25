import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, Integer, Float, Boolean, DateTime, ForeignKey, Text
)
from sqlalchemy.orm import relationship
from database import Base

def generate_uuid(prefix: str = "") -> str:
    return f"{prefix}{uuid.uuid4().hex[:10]}"

def utc_now() -> datetime:
    return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("u_"))
    username = Column(String(50), unique=True, nullable=False, index=True)
    email = Column(String(100), unique=True, nullable=True)
    profile_image = Column(String(255), nullable=True)
    country = Column(String(10), default="KR", nullable=False)
    is_creator = Column(Boolean, default=True, nullable=False)
    exact_location_consent = Column(Boolean, default=False, nullable=False)
    exact_location_consented_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)

    # Relationships
    videos = relationship("Video", back_populates="uploader", cascade="all, delete-orphan")
    support_account = relationship(
        "CreatorSupportAccount",
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )


class CreatorSupportAccount(Base):
    """
    CR-01: External Creator Support Account (Ko-fi, Buy Me a Coffee, PayPal.Me, etc.)
    NOWFIELD stores & verifies the external support URL only (0% platform fee, no internal wallet).
    """
    __tablename__ = "creator_support_accounts"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("sup_"))
    user_id = Column(String(50), ForeignKey("users.id"), unique=True, nullable=False, index=True)
    provider = Column(String(30), default="kofi", nullable=False)  # kofi, buymeacoffee, paypal
    support_url = Column(String(500), nullable=False)
    ownership_status = Column(String(20), default="verified", nullable=False)  # verified, pending, unverified, disconnected
    verified_at = Column(DateTime(timezone=True), nullable=True)
    active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now, nullable=False)

    user = relationship("User", back_populates="support_account")


class CaptureSession(Base):
    """
    Spec v1.1 Section 24: CaptureSession
    id, user_id, video_id, started_at, ended_at, app_integrity_result, upload_token, original_hash
    """
    __tablename__ = "capture_sessions"

    id = Column(String(64), primary_key=True, default=lambda: generate_uuid("cap_"))
    user_id = Column(String(50), ForeignKey("users.id"), nullable=False, index=True)
    video_id = Column(String(50), ForeignKey("videos.id"), nullable=True, index=True)
    started_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)
    ended_at = Column(DateTime(timezone=True), default=utc_now, nullable=True)
    app_integrity_result = Column(String(30), default="verified", nullable=False)
    upload_token = Column(String(100), nullable=True)
    original_hash = Column(String(64), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)


class SupportLinkEvent(Base):
    """
    Spec v1.1 Section 24 & CR-01: SupportLinkEvent
    id, video_id, creator_id, viewer_id, provider, clicked_at, session_id
    Statistical click log only (NOT treated as completed donation or revenue).
    """
    __tablename__ = "support_link_events"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("sle_"))
    video_id = Column(String(50), ForeignKey("videos.id"), nullable=False, index=True)
    creator_id = Column(String(50), ForeignKey("users.id"), nullable=False, index=True)
    viewer_id = Column(String(50), nullable=True, index=True)
    provider = Column(String(30), default="kofi", nullable=False)
    clicked_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)
    session_id = Column(String(64), nullable=True)



class Video(Base):
    __tablename__ = "videos"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("v_"))
    uploader_id = Column(String(50), ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(200), nullable=False)
    subtitle = Column(Text, nullable=True)
    video_url = Column(String(500), nullable=False)
    thumbnail_url = Column(String(500), nullable=True)
    preview_url = Column(String(500), nullable=True)
    duration_sec = Column(Integer, default=60, nullable=False)  # Max 60 seconds (One Minute rule)
    width = Column(Integer, nullable=True)
    height = Column(Integer, nullable=True)
    subtitles_json = Column(Text, nullable=True)

    # CR-02: Location Information (Internal capture coords vs Public display coords separated)
    capture_lat = Column(Float, nullable=False)   # Internal exact GPS only (never exposed to general user API)
    capture_lng = Column(Float, nullable=False)   # Internal exact GPS only (never exposed to general user API)
    latitude = Column(Float, nullable=False)      # Internal compatibility column (synced with capture_lat)
    longitude = Column(Float, nullable=False)     # Internal compatibility column (synced with capture_lng)
    location_display_mode = Column(String(20), default="exact", nullable=False, index=True)  # exact, approximate, hidden
    display_lat = Column(Float, nullable=True, index=True)   # Public coordinate (None when hidden)
    display_lng = Column(Float, nullable=True, index=True)   # Public coordinate (None when hidden)
    fuzzed_lat = Column(Float, nullable=True, index=True)    # Public coordinate alias (None when hidden)
    fuzzed_lng = Column(Float, nullable=True, index=True)    # Public coordinate alias (None when hidden)
    approx_radius_m = Column(Integer, default=150, nullable=True)  # 100~200m nominal range when approximate
    accuracy_m = Column(Float, default=10.0, nullable=True)
    location_name = Column(String(100), nullable=False)      # Administrative name or '위치 미표시' when hidden

    # Product Integrity & Status
    status = Column(String(20), default="public", index=True)  # public, private, reported
    is_original_capture = Column(Boolean, default=True, nullable=False)  # One Take rule
    original_hash = Column(String(64), nullable=True)                    # Video integrity hash

    # CR-01: Creator Support & Engagement (License fields removed)
    support_enabled = Column(Boolean, default=False, nullable=False)
    support_click_count = Column(Integer, default=0, nullable=False)
    like_count = Column(Integer, default=0, nullable=False)
    comment_count = Column(Integer, default=0, nullable=False)

    # CR-03: Separate Capture Timestamp vs Published Timestamp (UTC) + Display Timezone
    captured_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)
    published_at = Column(DateTime(timezone=True), default=utc_now, nullable=False, index=True)
    display_timezone = Column(String(50), default="Asia/Seoul", nullable=False)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False, index=True)

    # Relationships
    uploader = relationship("User", back_populates="videos")
    reports = relationship("Report", back_populates="video", cascade="all, delete-orphan")


class Report(Base):
    __tablename__ = "reports"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("rep_"))
    video_id = Column(String(50), ForeignKey("videos.id"), nullable=False, index=True)
    reporter_id = Column(String(50), ForeignKey("users.id"), nullable=False)
    reason = Column(String(50), nullable=False)  # sexual_content, violence, privacy, spam, copyright
    details = Column(Text, nullable=True)
    status = Column(String(20), default="pending", nullable=False) # pending, action_taken, dismissed
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)

    # Relationships
    video = relationship("Video", back_populates="reports")


class UserBlock(Base):
    __tablename__ = "user_blocks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    blocker_id = Column(String(50), ForeignKey("users.id"), nullable=False, index=True)
    blocked_id = Column(String(50), ForeignKey("users.id"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)


class VideoLike(Base):
    __tablename__ = "video_likes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    video_id = Column(String(50), ForeignKey("videos.id"), nullable=False, index=True)
    user_id = Column(String(50), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)


class Comment(Base):
    __tablename__ = "comments"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("cmt_"))
    video_id = Column(String(50), ForeignKey("videos.id"), nullable=False, index=True)
    user_id = Column(String(50), nullable=False, index=True)
    username = Column(String(50), nullable=False, default="@seoul_walker")
    content = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)


class UserFollow(Base):
    __tablename__ = "user_follows"

    id = Column(Integer, primary_key=True, autoincrement=True)
    follower_id = Column(String(50), nullable=False, index=True)
    following_id = Column(String(50), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)


class AdCampaign(Base):
    """
    Spec v1.1 Section 11: Native Feed Ad Campaign & Web Ad Network (Kakao AdFit / Google AdSense)
    30% of net ad revenue is accumulated into the Creator Pool.
    """
    __tablename__ = "ad_campaigns"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("ad_"))
    network = Column(String(30), default="adfit", nullable=False)  # adfit, adsense, sponsor
    ad_unit_id = Column(String(120), nullable=True)  # e.g. DAN-xxxxxx (Kakao AdFit) or ca-pub-xxx (AdSense)
    sponsor_name = Column(String(100), nullable=False)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=False)
    image_url = Column(String(500), nullable=False)
    target_url = Column(String(500), nullable=False)
    cta_label = Column(String(50), default="자세히 알아보기", nullable=False)
    impression_revenue_krw = Column(Integer, default=50, nullable=False)
    click_revenue_krw = Column(Integer, default=350, nullable=False)
    impression_count = Column(Integer, default=0, nullable=False)
    click_count = Column(Integer, default=0, nullable=False)
    active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)


class AdRevenueEvent(Base):
    """
    Spec v1.1 Section 11 & 13: Records ad impressions and clicks,
    accumulating 30% net revenue into the Creator Pool.
    """
    __tablename__ = "ad_revenue_events"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("arev_"))
    ad_id = Column(String(50), ForeignKey("ad_campaigns.id"), nullable=False, index=True)
    event_type = Column(String(20), nullable=False, index=True)  # impression, click
    viewer_id = Column(String(50), nullable=True, index=True)
    gross_revenue_krw = Column(Integer, default=0, nullable=False)
    creator_pool_krw = Column(Integer, default=0, nullable=False)  # 30% of gross_revenue_krw
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)

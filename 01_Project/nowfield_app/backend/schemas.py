from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field

# --- Creator Support Account Schemas (CR-01) ---

class SupportAccountUpsert(BaseModel):
    provider: str = Field(default="kofi", description="kofi, buymeacoffee, paypal")
    support_url: str = Field(..., description="Public HTTPS creator support page URL")

class SupportAccountResponse(BaseModel):
    id: str
    user_id: str
    provider: str
    support_url: str
    ownership_status: str  # verified, pending, unverified, disconnected
    verified_at: Optional[datetime] = None
    active: bool

    model_config = ConfigDict(from_attributes=True)

class SupportClickResponse(BaseModel):
    video_id: str
    support_url: Optional[str] = None
    provider: Optional[str] = None
    click_count: int
    platform_fee_percent: int = 0

# --- User Schemas ---

class UserBase(BaseModel):
    username: str
    email: Optional[str] = None
    profile_image: Optional[str] = None
    country: str = "KR"
    is_creator: bool = True

class UserCreate(UserBase):
    id: Optional[str] = None

class UserResponse(UserBase):
    id: str
    exact_location_consent: bool = False
    exact_location_consented_at: Optional[datetime] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

# --- Video Schemas (CR-01, CR-02, CR-03) ---

class VideoCreate(BaseModel):
    uploader_id: str
    title: str = Field(..., max_length=200)
    video_url: str
    subtitle: Optional[str] = None
    thumbnail_url: Optional[str] = None
    latitude: float
    longitude: float
    duration_sec: int = Field(default=60, le=60)  # Max 60 seconds
    is_original_capture: bool = True
    # CR-01: Video-level support button toggle
    support_enabled: bool = False
    # CR-02: Location display mode & consent
    location_display_mode: str = Field(default="exact", description="exact, approximate, hidden")
    exact_location_consented: bool = False
    precise_permission_granted: bool = True
    is_sensitive_place: bool = False
    accuracy_m: Optional[float] = 10.0
    # CR-03: Capture timestamp & display timezone
    captured_at: Optional[datetime] = None
    display_timezone: str = "Asia/Seoul"
    capture_session_id: Optional[str] = None


class VideoSettingsUpdate(BaseModel):
    """
    Spec v1.1 Principle 8 (Privacy by Choice) & CR-01/CR-02:
    Allows creator to update per-video support_enabled and location_display_mode at any time.
    """
    requester_id: Optional[str] = "u_seoul_walker"
    support_enabled: Optional[bool] = None
    location_display_mode: Optional[str] = Field(
        default=None, description="exact, approximate, hidden"
    )
    exact_location_consented: Optional[bool] = None
    precise_permission_granted: bool = True
    is_sensitive_place: bool = False

class VideoResponse(BaseModel):
    """
    CR-02: General user API response NEVER returns capture_lat/capture_lng raw coordinates!
    Only returns display_lat/display_lng according to location_display_mode (None when hidden).
    """
    id: str
    uploader_id: str
    uploader_name: Optional[str] = None
    title: str
    subtitle: Optional[str] = None
    video_url: str
    thumbnail_url: Optional[str] = None
    preview_url: Optional[str] = None
    duration_sec: int
    width: Optional[int] = None
    height: Optional[int] = None
    subtitles_json: Optional[str] = None

    # CR-02: Public Location Information
    location_display_mode: str = "exact"   # exact, approximate, hidden
    location_privacy_label: str = "정확한 위치"  # 정확한 위치 | 약 100~200m 범위 | 위치 미표시
    display_lat: Optional[float] = None
    display_lng: Optional[float] = None
    fuzzed_lat: Optional[float] = None
    fuzzed_lng: Optional[float] = None
    approx_radius_m: Optional[int] = None
    location_name: str
    status: str
    is_original_capture: bool

    # CR-01: Creator Support (License fields removed)
    support_enabled: bool = False
    creator_support_url: Optional[str] = None
    creator_support_provider: Optional[str] = None
    support_click_count: int = 0

    like_count: int
    comment_count: int

    # CR-03: Absolute Published Timestamp vs Capture Timestamp
    published_at: datetime
    captured_at: Optional[datetime] = None
    display_timezone: str = "Asia/Seoul"
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

class VideoCluster(BaseModel):
    cluster_id: str
    location_name: str
    latitude: float
    longitude: float
    video_count: int
    is_stacked: bool
    videos: List[VideoResponse]

class NearbyResponse(BaseModel):
    center_lat: float
    center_lng: float
    radius_km: float
    time_limit_minutes: int = 60
    total_videos: int
    clusters: List[VideoCluster]
    raw_videos: List[VideoResponse]

# --- Report Schemas ---

class ReportCreate(BaseModel):
    video_id: str
    reporter_id: str
    reason: str  # sexual_content, violence, privacy, spam, copyright
    details: Optional[str] = None

class ReportResponse(BaseModel):
    id: str
    video_id: str
    reporter_id: str
    reason: str
    details: Optional[str] = None
    status: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

# --- Like & Comment Schemas ---

class LikeToggleResponse(BaseModel):
    video_id: str
    liked: bool
    like_count: int

class CommentCreate(BaseModel):
    user_id: str = "u_seoul_walker"
    username: str = "@seoul_walker"
    content: str = Field(..., min_length=1, max_length=500)

class CommentResponse(BaseModel):
    id: str
    video_id: str
    user_id: str
    username: str
    content: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

# --- Profile Summary Schema (CR-01: License fields removed, Support Account added) ---

class UserProfileSummaryResponse(BaseModel):
    user: UserResponse
    video_count: int
    follower_count: int = 0
    following_count: int = 0
    is_following: bool = False
    support_account: Optional[SupportAccountResponse] = None
    total_support_clicks: int = 0
    ad_creator_pool_revenue: int = 51240
    videos: List[VideoResponse] = []

class FollowToggleResponse(BaseModel):
    target_user_id: str
    following: bool
    follower_count: int

class SearchResponse(BaseModel):
    query: str
    category: Optional[str] = None
    videos: List[VideoResponse] = []
    users: List[UserResponse] = []
    places: List[dict] = []

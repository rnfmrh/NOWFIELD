from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field

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
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

# --- Video Schemas ---

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
    license_price: int = 10000

class VideoResponse(BaseModel):
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
    # Note: Precise latitude and longitude are omitted or fuzzed in public responses!
    fuzzed_lat: float
    fuzzed_lng: float
    location_name: str
    status: str
    is_original_capture: bool
    license_price: int
    like_count: int
    comment_count: int
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
    total_videos: int
    clusters: List[VideoCluster]
    raw_videos: List[VideoResponse]

# --- License Schemas ---

class LicenseCreate(BaseModel):
    video_id: str
    buyer_id: str

class LicenseResponse(BaseModel):
    id: str
    video_id: str
    buyer_id: str
    seller_id: str
    total_amount: int
    creator_payout: int
    platform_fee: int
    status: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

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

# --- Profile Summary Schema ---

class UserProfileSummaryResponse(BaseModel):
    user: UserResponse
    video_count: int
    follower_count: int = 0
    following_count: int = 0
    is_following: bool = False
    total_license_sales: int = 0
    total_creator_revenue: int = 0
    videos: List[VideoResponse] = []
    licensed_videos: List[VideoResponse] = []

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

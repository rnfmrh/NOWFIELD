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
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)

    # Relationships
    videos = relationship("Video", back_populates="uploader", cascade="all, delete-orphan")
    purchased_licenses = relationship("LicenseTransaction", foreign_keys="LicenseTransaction.buyer_id", back_populates="buyer")
    earned_licenses = relationship("LicenseTransaction", foreign_keys="LicenseTransaction.seller_id", back_populates="seller")

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

    # Location Information
    latitude = Column(Float, nullable=False)    # Exact GPS (internal storage only)
    longitude = Column(Float, nullable=False)   # Exact GPS (internal storage only)
    fuzzed_lat = Column(Float, nullable=False, index=True)  # Fuzzed public GPS (~150m grid)
    fuzzed_lng = Column(Float, nullable=False, index=True)  # Fuzzed public GPS (~150m grid)
    location_name = Column(String(100), nullable=False)     # Kakao Reverse Geocoded (e.g. 서울 강남구 신사동)

    # Product Integrity & Status
    status = Column(String(20), default="public", index=True)  # public, private, reported
    is_original_capture = Column(Boolean, default=True, nullable=False)  # One Take rule
    original_hash = Column(String(64), nullable=True)                    # Video integrity hash

    # Economics & Engagement
    license_price = Column(Integer, default=10000, nullable=False)  # Standard KRW 10,000
    like_count = Column(Integer, default=0, nullable=False)
    comment_count = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False, index=True)

    # Relationships
    uploader = relationship("User", back_populates="videos")
    licenses = relationship("LicenseTransaction", back_populates="video", cascade="all, delete-orphan")
    reports = relationship("Report", back_populates="video", cascade="all, delete-orphan")

class LicenseTransaction(Base):
    __tablename__ = "license_transactions"

    id = Column(String(50), primary_key=True, default=lambda: generate_uuid("lic_"))
    video_id = Column(String(50), ForeignKey("videos.id"), nullable=False, index=True)
    buyer_id = Column(String(50), ForeignKey("users.id"), nullable=False, index=True)
    seller_id = Column(String(50), ForeignKey("users.id"), nullable=False, index=True)

    total_amount = Column(Integer, default=10000, nullable=False)  # Total sales price
    creator_payout = Column(Integer, default=8000, nullable=False) # 80% to creator
    platform_fee = Column(Integer, default=2000, nullable=False)   # 20% to platform
    status = Column(String(20), default="completed", nullable=False)
    created_at = Column(DateTime(timezone=True), default=utc_now, nullable=False)

    # Relationships
    video = relationship("Video", back_populates="licenses")
    buyer = relationship("User", foreign_keys=[buyer_id], back_populates="purchased_licenses")
    seller = relationship("User", foreign_keys=[seller_id], back_populates="earned_licenses")

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

import os
import math
import hashlib
from typing import Optional, Dict, Any, List, Tuple
import httpx
from dotenv import load_dotenv

load_dotenv()

KAKAO_REST_API_KEY = os.getenv("KAKAO_REST_API_KEY", "")
KAKAO_API_BASE = "https://dapi.kakao.com/v2/local"

KNOWN_KOREAN_DONGS: List[Tuple[str, float, float]] = [
    ("서울 강남구 신사동", 37.5204, 127.0229),
    ("서울 강남구 압구정동", 37.5270, 127.0284),
    ("서울 강남구 청담동", 37.5240, 127.0470),
    ("서울 강남구 논현동", 37.5110, 127.0310),
    ("서울 강남구 삼성동", 37.5140, 127.0565),
    ("서울 강남구 역삼동", 37.5006, 127.0365),
    ("서울 강남구 대치동", 37.4945, 127.0620),
    ("서울 서초구 잠원동", 37.5180, 127.0160),
    ("서울 서초구 반포동", 37.5045, 127.0048),
    ("서울 서초구 서초동", 37.4915, 127.0150),
    ("서울 서초구 양재동", 37.4740, 127.0380),
    ("서울 용산구 한남동", 37.5345, 127.0010),
    ("서울 용산구 이태원동", 37.5345, 126.9945),
    ("서울 성동구 성수동", 37.5445, 127.0560),
    ("서울 성동구 옥수동", 37.5425, 127.0155),
    ("서울 마포구 서교동", 37.5540, 126.9210),
    ("서울 마포구 연남동", 37.5635, 126.9245),
    ("서울 중구 명동", 37.5635, 126.9850),
    ("서울 종로구 종로1가", 37.5700, 126.9800),
    ("서울 송파구 잠실동", 37.5130, 127.1000),
    ("서울 영등포구 여의도동", 37.5250, 126.9260),
]


def fallback_korean_dong_name(latitude: float, longitude: float) -> str:
    """
    When Kakao REST API key is not configured or offline, resolve coordinates
    to the nearest neighborhood (동) name instead of raw decimal coordinates.
    """
    best_name = "서울 강남구 신사동"
    best_dist = float("inf")
    for name, d_lat, d_lng in KNOWN_KOREAN_DONGS:
        dist = haversine_distance_meters(latitude, longitude, d_lat, d_lng)
        if dist < best_dist:
            best_dist = dist
            best_name = name
    return best_name


class KakaoLocalService:
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or KAKAO_REST_API_KEY
        self.headers = {
            "Authorization": f"KakaoAK {self.api_key}"
        }

    async def coord_to_region(self, latitude: float, longitude: float) -> Dict[str, Any]:
        """
        Convert GPS coordinate (lat, lng) to administrative & legal region name.
        Uses Kakao coord2regioncode API, with OpenStreetMap Nominatim & nearest-dong fallback
        so it NEVER returns raw coordinates like '37.5204, 127.0229'.
        """
        if self.api_key:
            url = f"{KAKAO_API_BASE}/geo/coord2regioncode.json"
            params = {
                "x": longitude,
                "y": latitude,
            }

            try:
                async with httpx.AsyncClient(timeout=4.0) as client:
                    res = await client.get(url, params=params, headers=self.headers)
                    if res.status_code == 200:
                        data = res.json()
                        documents = data.get("documents", [])
                        if documents:
                            adm_region = next(
                                (d for d in documents if d.get("region_type") == "H"),
                                documents[0],
                            )
                            depth1 = adm_region.get("region_1depth_name", "")
                            depth2 = adm_region.get("region_2depth_name", "")
                            depth3 = adm_region.get("region_3depth_name", "")
                            short_depth1 = (
                                depth1.replace("특별시", "")
                                .replace("광역시", "")
                                .replace("특별자치시", "")
                                .replace("특별자치도", "")
                            )
                            formatted_name = f"{short_depth1} {depth2} {depth3}".strip()
                            if formatted_name:
                                return {
                                    "full_address": adm_region.get("address_name", ""),
                                    "formatted_name": formatted_name,
                                    "depth1": depth1,
                                    "depth2": depth2,
                                    "depth3": depth3,
                                    "region_type": adm_region.get("region_type"),
                                    "documents": documents,
                                }
            except Exception:
                pass

        # Fallback 1: OpenStreetMap Nominatim reverse geocoding (Korean administrative dong)
        try:
            nom_url = "https://nominatim.openstreetmap.org/reverse"
            nom_params = {
                "lat": latitude,
                "lon": longitude,
                "format": "jsonv2",
                "accept-language": "ko",
                "zoom": 16,
            }
            nom_headers = {"User-Agent": "NOWFIELD-FieldApp/1.5"}
            async with httpx.AsyncClient(timeout=3.0) as client:
                nres = await client.get(nom_url, params=nom_params, headers=nom_headers)
                if nres.status_code == 200:
                    ndata = nres.json()
                    addr = ndata.get("address", {})
                    city = (
                        addr.get("city")
                        or addr.get("province")
                        or addr.get("state")
                        or ""
                    )
                    city = (
                        city.replace("특별시", "")
                        .replace("광역시", "")
                        .replace("특별자치시", "")
                        .replace("특별자치도", "")
                    )
                    borough = (
                        addr.get("borough")
                        or addr.get("county")
                        or addr.get("city_district")
                        or ""
                    )
                    dong = (
                        addr.get("quarter")
                        or addr.get("suburb")
                        or addr.get("neighbourhood")
                        or addr.get("village")
                        or addr.get("town")
                        or ""
                    )
                    parts = [p for p in (city, borough, dong) if p]
                    # Deduplicate consecutive identical parts
                    dedup: List[str] = []
                    for p in parts:
                        if not dedup or dedup[-1] != p:
                            dedup.append(p)
                    if dedup and any(
                        p.endswith(("동", "읍", "면", "가", "리", "로")) for p in dedup
                    ):
                        formatted = " ".join(dedup)
                        return {
                            "full_address": ndata.get("display_name", formatted),
                            "formatted_name": formatted,
                            "depth1": city,
                            "depth2": borough,
                            "depth3": dong,
                        }
        except Exception:
            pass

        # Fallback 2: Deterministic nearest Korean neighborhood (동) lookup
        dong_name = fallback_korean_dong_name(latitude, longitude)
        return {"formatted_name": dong_name, "raw": None}

    async def coord_to_address(self, latitude: float, longitude: float) -> Dict[str, Any]:
        """
        Convert coordinate to detailed road/lot-number address.
        """
        if not self.api_key:
            return {}

        url = f"{KAKAO_API_BASE}/geo/coord2address.json"
        params = {"x": longitude, "y": latitude}

        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                res = await client.get(url, params=params, headers=self.headers)
                if res.status_code == 200:
                    return res.json()
                return {"error": res.text}
        except Exception as e:
            return {"error": str(e)}

    async def search_places(self, query: str, latitude: Optional[float] = None, longitude: Optional[float] = None, radius: int = 1000) -> List[Dict[str, Any]]:
        """
        Search places/landmarks by keyword.
        """
        if not self.api_key or not query:
            return []

        url = f"{KAKAO_API_BASE}/search/keyword.json"
        params: Dict[str, Any] = {"query": query}
        if latitude is not None and longitude is not None:
            params["x"] = longitude
            params["y"] = latitude
            params["radius"] = radius
            params["sort"] = "distance"

        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                res = await client.get(url, params=params, headers=self.headers)
                if res.status_code == 200:
                    return res.json().get("documents", [])
                return []
        except Exception:
            return []

def haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great-circle distance between two points in meters.
    """
    R = 6371000.0  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (math.sin(delta_phi / 2.0) ** 2 +
         math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2)
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return R * c

def fuzz_coordinates(lat: float, lon: float, precision_meters: float = 150.0) -> tuple:
    """
    Apply coordinate fuzzing for privacy protection (NOWFIELD Spec rule #59).
    Rounds coordinates to grid cells roughly equal to precision_meters.
    1 degree latitude ~ 111,000 meters.
    1 degree longitude at Seoul (~37 deg) ~ 88,000 meters.
    """
    lat_step = precision_meters / 111000.0
    lon_step = precision_meters / (111000.0 * math.cos(math.radians(lat)))

    fuzzed_lat = round(lat / lat_step) * lat_step
    fuzzed_lon = round(lon / lon_step) * lon_step
    return (round(fuzzed_lat, 5), round(fuzzed_lon, 5))


def generate_approximate_coordinates(
    lat: float,
    lon: float,
    video_id: str,
    min_radius_m: float = 100.0,
    max_radius_m: float = 200.0,
) -> Tuple[float, float, int]:
    """
    CR-02.C: Generate a deterministic 100~200m generalized/fuzzed public coordinate
    for a given video_id so that:
    1) Repeated fetches never move the pin (consistent per video_id).
    2) Multiple videos from the same spot do not share an identical offset pattern.
    3) Exact distance is not exposed (returns a standard 150m nominal radius label).
    """
    digest = hashlib.sha256(f"nowfield_approx_v1:{video_id}".encode("utf-8")).digest()
    r_Ratio = int.from_bytes(digest[:4], "big") / 0xFFFFFFFF
    angle_ratio = int.from_bytes(digest[4:8], "big") / 0xFFFFFFFF

    distance_m = min_radius_m + (max_radius_m - min_radius_m) * r_Ratio
    theta = 2.0 * math.pi * angle_ratio

    delta_lat = (distance_m * math.cos(theta)) / 111000.0
    cos_lat = max(0.2, math.cos(math.radians(lat)))
    delta_lon = (distance_m * math.sin(theta)) / (111000.0 * cos_lat)

    approx_lat = round(lat + delta_lat, 5)
    approx_lon = round(lon + delta_lon, 5)
    return approx_lat, approx_lon, 150


kakao_service = KakaoLocalService()

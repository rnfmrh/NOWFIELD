import os
import math
from typing import Optional, Dict, Any, List
import httpx
from dotenv import load_dotenv

load_dotenv()

KAKAO_REST_API_KEY = os.getenv("KAKAO_REST_API_KEY", "")
KAKAO_API_BASE = "https://dapi.kakao.com/v2/local"

class KakaoLocalService:
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or KAKAO_REST_API_KEY
        self.headers = {
            "Authorization": f"KakaoAK {self.api_key}"
        }

    async def coord_to_region(self, latitude: float, longitude: float) -> Dict[str, Any]:
        """
        Convert GPS coordinate (lat, lng) to administrative & legal region name.
        Uses Kakao coord2regioncode API.
        Note: Kakao expects x=longitude, y=latitude.
        """
        if not self.api_key:
            return {"formatted_name": f"{latitude:.4f}, {longitude:.4f}", "raw": None}

        url = f"{KAKAO_API_BASE}/geo/coord2regioncode.json"
        params = {
            "x": longitude,
            "y": latitude,
        }

        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                res = await client.get(url, params=params, headers=self.headers)
                if res.status_code != 200:
                    return {"formatted_name": f"{latitude:.4f}, {longitude:.4f}", "error": res.text}
                
                data = res.json()
                documents = data.get("documents", [])
                if not documents:
                    return {"formatted_name": f"{latitude:.4f}, {longitude:.4f}", "documents": []}

                # Prefer administrative dong (H: 행정동) or legal dong (B: 법정동)
                # Usually type "H" (행정동) is best for current real-time community / location
                adm_region = next((d for d in documents if d.get("region_type") == "H"), documents[0])
                
                depth1 = adm_region.get("region_1depth_name", "")
                depth2 = adm_region.get("region_2depth_name", "")
                depth3 = adm_region.get("region_3depth_name", "")

                # Simplified clean name (e.g., "서울 강남구 신사동" or "강남구 신사동")
                short_depth1 = depth1.replace("특별시", "").replace("광역시", "")
                formatted_name = f"{short_depth1} {depth2} {depth3}".strip()

                return {
                    "full_address": adm_region.get("address_name", ""),
                    "formatted_name": formatted_name,
                    "depth1": depth1,
                    "depth2": depth2,
                    "depth3": depth3,
                    "region_type": adm_region.get("region_type"),
                    "documents": documents
                }
        except Exception as e:
            return {"formatted_name": f"{latitude:.4f}, {longitude:.4f}", "error": str(e)}

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

kakao_service = KakaoLocalService()

import requests
from django.core.cache import cache
from .cache_utils import jittered_ttl

OSRM_BASE_URL = "http://router.project-osrm.org/route/v1/driving"

# Base TTL for OSRM route results.
# Actual TTL = jittered_ttl(OSRM_CACHE_TTL, 10) → 20–40 s
# Short enough to reflect vehicle movement, long enough to absorb burst
# dispatch requests querying the same corridor simultaneously.
OSRM_CACHE_TTL = 30          # base seconds
OSRM_CACHE_JITTER = 10       # ±10 s

# Round coordinates to 4 decimal places (~11 m) for cache-key stability.
_COORD_PRECISION = 4


def _cache_key(origin_lat, origin_lng, dest_lat, dest_lng) -> str:
    return (
        f"osrm_route:"
        f"{round(origin_lat, _COORD_PRECISION)}:{round(origin_lng, _COORD_PRECISION)}:"
        f"{round(dest_lat, _COORD_PRECISION)}:{round(dest_lng, _COORD_PRECISION)}"
    )


def get_route_distance(origin_lat, origin_lng, dest_lat, dest_lng):
    """
    Returns (distance_km, duration_min, geometry) using real road routing via OSRM.
    geometry is a list of [lat, lng] points forming the route path.
    Returns (None, None, None) if OSRM is unreachable or has no route.

    Results are cached in Redis with a jittered TTL (base 30 s ± 10 s) to:
      - Avoid repeated HTTP calls during burst dispatch requests.
      - Stagger expiry times and prevent thundering-herd cache stampedes.
    """
    key = _cache_key(origin_lat, origin_lng, dest_lat, dest_lng)

    cached = cache.get(key)
    if cached is not None:
        return cached['distance_km'], cached['duration_min'], cached['geometry']

    url = f"{OSRM_BASE_URL}/{origin_lng},{origin_lat};{dest_lng},{dest_lat}"
    params = {"overview": "full", "geometries": "geojson"}

    try:
        response = requests.get(url, params=params, timeout=3)
        response.raise_for_status()
        data = response.json()

        if data.get("code") != "Ok" or not data.get("routes"):
            return None, None, None

        route = data["routes"][0]
        distance_km = round(route["distance"] / 1000, 2)
        duration_min = round(route["duration"] / 60, 2)

        # GeoJSON gives [lng, lat] pairs — flip to [lat, lng] for Leaflet
        coords = route["geometry"]["coordinates"]
        geometry = [[lat, lng] for lng, lat in coords]

        # Store in Redis with jitter (silently skipped if Redis is unavailable)
        cache.set(key, {
            'distance_km': distance_km,
            'duration_min': duration_min,
            'geometry': geometry,
        }, timeout=jittered_ttl(OSRM_CACHE_TTL, OSRM_CACHE_JITTER))

        return distance_km, duration_min, geometry

    except (requests.RequestException, KeyError, ValueError, TypeError):
        return None, None, None
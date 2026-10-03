import math
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

# Douglas-Peucker tolerance in degrees (~50 m).
# Higher values produce smoother lines but lose small-road fidelity.
# 0.0005° ≈ 55 m at Nepal's latitude — good balance between smoothness
# and staying visually on-road at typical zoom levels.
_SIMPLIFY_TOLERANCE = 0.0005


# ───────────────── geometry simplification ─────────────────

def _perpendicular_distance(point, line_start, line_end):
    """Perpendicular distance from *point* to the line segment
    defined by *line_start* → *line_end*.  All inputs are [lat, lng]."""
    x0, y0 = point
    x1, y1 = line_start
    x2, y2 = line_end

    dx = x2 - x1
    dy = y2 - y1
    denom = math.hypot(dx, dy)
    if denom == 0:
        return math.hypot(x0 - x1, y0 - y1)
    return abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1) / denom


def _douglas_peucker(points, tolerance):
    """Ramer–Douglas–Peucker line simplification.

    Removes intermediate points that deviate less than *tolerance* from
    the straight line between their neighbours.  Keeps endpoints and all
    structurally significant bends.
    """
    if len(points) <= 2:
        return points

    # Find the point with the maximum distance from the line start→end
    max_dist = 0.0
    max_idx = 0
    for i in range(1, len(points) - 1):
        d = _perpendicular_distance(points[i], points[0], points[-1])
        if d > max_dist:
            max_dist = d
            max_idx = i

    if max_dist > tolerance:
        left = _douglas_peucker(points[:max_idx + 1], tolerance)
        right = _douglas_peucker(points[max_idx:], tolerance)
        return left[:-1] + right
    else:
        return [points[0], points[-1]]


def _simplify_geometry(geometry, tolerance=_SIMPLIFY_TOLERANCE):
    """Simplify a route geometry list of [lat, lng] points.

    Returns a new list with redundant intermediate points removed.
    Always preserves at least the start and end points.
    """
    if not geometry or len(geometry) <= 2:
        return geometry
    return _douglas_peucker(geometry, tolerance)


# ───────────────── cache keys ─────────────────

def _cache_key(origin_lat, origin_lng, dest_lat, dest_lng) -> str:
    return (
        f"osrm_route:"
        f"{round(origin_lat, _COORD_PRECISION)}:{round(origin_lng, _COORD_PRECISION)}:"
        f"{round(dest_lat, _COORD_PRECISION)}:{round(dest_lng, _COORD_PRECISION)}"
    )


def _waypoints_cache_key(waypoints) -> str:
    """Cache key for a multi-waypoint route."""
    parts = [
        f"{round(lat, _COORD_PRECISION)}:{round(lng, _COORD_PRECISION)}"
        for lat, lng in waypoints
    ]
    return f"osrm_wp_route:{':'.join(parts)}"


# ───────────────── route helpers ─────────────────

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
    params = {
        "overview": "full",
        "geometries": "geojson",
        "continue_straight": "true",   # avoid unnecessary U-turns / detours
        "alternatives": "false",
    }

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

        # Simplify to remove visual noise while staying on-road
        geometry = _simplify_geometry(geometry)

        # Store in Redis with jitter (silently skipped if Redis is unavailable)
        cache.set(key, {
            'distance_km': distance_km,
            'duration_min': duration_min,
            'geometry': geometry,
        }, timeout=jittered_ttl(OSRM_CACHE_TTL, OSRM_CACHE_JITTER))

        return distance_km, duration_min, geometry

    except (requests.RequestException, KeyError, ValueError, TypeError):
        return None, None, None


def get_route_through_waypoints(waypoints):
    """Route through N waypoints: [(lat, lng), (lat, lng), ...].

    Returns (distance_km, duration_min, geometry) for the full route.
    geometry is a list of [lat, lng] points.
    Returns (None, None, None) on failure.
    """
    if len(waypoints) < 2:
        return None, None, None

    key = _waypoints_cache_key(waypoints)
    cached = cache.get(key)
    if cached is not None:
        return cached['distance_km'], cached['duration_min'], cached['geometry']

    coords_str = ";".join(f"{lng},{lat}" for lat, lng in waypoints)
    url = f"{OSRM_BASE_URL}/{coords_str}"
    params = {
        "overview": "full",
        "geometries": "geojson",
        "continue_straight": "true",   # avoid unnecessary U-turns / detours
        "alternatives": "false",
    }

    try:
        response = requests.get(url, params=params, timeout=5)
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

        # Simplify to remove visual noise while staying on-road
        geometry = _simplify_geometry(geometry)

        cache.set(key, {
            'distance_km': distance_km,
            'duration_min': duration_min,
            'geometry': geometry,
        }, timeout=jittered_ttl(OSRM_CACHE_TTL, OSRM_CACHE_JITTER))

        return distance_km, duration_min, geometry

    except (requests.RequestException, KeyError, ValueError, TypeError):
        return None, None, None
import requests

OSRM_BASE_URL = "http://router.project-osrm.org/route/v1/driving"


def get_route_distance(origin_lat, origin_lng, dest_lat, dest_lng):
    """
    Returns (distance_km, duration_min) using real road routing via OSRM.
    Returns (None, None) if OSRM is unreachable or returns no route, so
    callers can fall back to straight-line distance instead of crashing.
    """
    url = f"{OSRM_BASE_URL}/{origin_lng},{origin_lat};{dest_lng},{dest_lat}"
    params = {"overview": "false"}

    try:
        response = requests.get(url, params=params, timeout=3)
        response.raise_for_status()
        data = response.json()

        if data.get("code") != "Ok" or not data.get("routes"):
            return None, None

        route = data["routes"][0]
        distance_km = route["distance"] / 1000
        duration_min = route["duration"] / 60
        return round(distance_km, 2), round(duration_min, 2)

    except (requests.RequestException, KeyError, ValueError, TypeError):
        return None, None
import requests

OSRM_BASE_URL = "http://router.project-osrm.org/route/v1/driving"


def get_route_distance(origin_lat, origin_lng, dest_lat, dest_lng):
    """
    Returns (distance_km, duration_min, geometry) using real road routing via OSRM.
    geometry is a list of [lat, lng] points forming the route path.
    Returns (None, None, None) if OSRM is unreachable or has no route.
    """
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

        return distance_km, duration_min, geometry

    except (requests.RequestException, KeyError, ValueError, TypeError):
        return None, None, None
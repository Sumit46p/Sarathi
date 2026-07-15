from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance
from django.utils import timezone
from .osrm import get_route_distance

from .models import Vehicle, DispatchRequest, Driver
from .serializers import (
    VehicleSerializer,
    LocationUpdateSerializer,
    NearestVehicleSerializer,
    DispatchRequestInputSerializer,
    DispatchRequestSerializer,
    DriverSerializer,
    AssignDriverSerializer,
)


class VehicleListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/vehicles/      — list all vehicles with current location
    POST /api/vehicles/      — create a new vehicle (for testing without admin)
    """
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Vehicle.objects.filter(owner=self.request.user)

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)


class VehicleDetailView(generics.RetrieveUpdateDestroyAPIView):
    """
    GET    /api/vehicles/<id>/  — detail of one vehicle
    PATCH  /api/vehicles/<id>/  — partial update (toggle is_available, edit details)
    DELETE /api/vehicles/<id>/  — remove a vehicle
    """
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Vehicle.objects.filter(owner=self.request.user)


class DriverListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/drivers/      — list all drivers
    POST /api/drivers/      — create a new driver
    """
    serializer_class = DriverSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Driver.objects.filter(owner=self.request.user)

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)


class DriverDetailView(generics.RetrieveUpdateDestroyAPIView):
    """
    GET    /api/drivers/<id>/  — detail of one driver
    PATCH  /api/drivers/<id>/  — partial update
    DELETE /api/drivers/<id>/  — remove a driver
    """
    serializer_class = DriverSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Driver.objects.filter(owner=self.request.user)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def update_location(request, pk):
    """
    POST /api/vehicles/<id>/update-location/
    Body: {"lat": 26.54, "lng": 87.89}

    Updates the vehicle's GPS location and returns the updated vehicle.
    """
    try:
        vehicle = Vehicle.objects.get(pk=pk, owner=request.user)
    except Vehicle.DoesNotExist:
        return Response(
            {'error': f'Vehicle {pk} not found or access denied'},
            status=status.HTTP_404_NOT_FOUND,
        )

    serializer = LocationUpdateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    vehicle.location = Point(
        serializer.validated_data['lng'],
        serializer.validated_data['lat'],
        srid=4326,
    )
    vehicle.last_location_at = timezone.now()
    vehicle.save(update_fields=['location', 'last_location_at'])

    return Response(VehicleSerializer(vehicle).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def assign_driver(request, pk):
    """
    POST /api/vehicles/<id>/assign-driver/
    Body: {"driver_id": 5} or {"driver_id": null}
    """
    try:
        vehicle = Vehicle.objects.get(pk=pk, owner=request.user)
    except Vehicle.DoesNotExist:
        return Response(
            {'error': 'Vehicle not found or access denied'},
            status=status.HTTP_404_NOT_FOUND,
        )

    serializer = AssignDriverSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    driver_id = serializer.validated_data.get('driver_id')
    if driver_id is None:
        vehicle.driver = None
    else:
        try:
            driver = Driver.objects.get(pk=driver_id, owner=request.user)
            vehicle.driver = driver
        except Driver.DoesNotExist:
            return Response(
                {'error': 'Driver not found or access denied'},
                status=status.HTTP_404_NOT_FOUND,
            )

    vehicle.save(update_fields=['driver'])
    return Response(VehicleSerializer(vehicle).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def nearest_vehicles(request):
    """
    GET /api/vehicles/nearest/?lat=..&lng=..&type=..
    Returns the top 5 available vehicles of the given type ordered by
    straight-line PostGIS distance. Scoped to request.user.
    """
    try:
        lat = float(request.query_params['lat'])
        lng = float(request.query_params['lng'])
        vehicle_type = request.query_params['type']
    except (KeyError, ValueError):
        return Response(
            {'error': 'Required query params: lat, lng, type'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    request_point = Point(lng, lat, srid=4326)

    vehicles = (
        Vehicle.objects
        .filter(owner=request.user, is_available=True, vehicle_type=vehicle_type)
        .annotate(distance=Distance('location', request_point))
        .order_by('distance')[:5]
    )

    results = []
    for v in vehicles:
        results.append({
            'id': v.id,
            'name': v.name,
            'distance_km': round(v.distance.km, 2),
            'lat': v.location.y,
            'lng': v.location.x,
        })

    serializer = NearestVehicleSerializer(results, many=True)
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def dispatch_vehicle(request):
    """
    POST /api/dispatch/
    Body: {"lat": ..., "lng": ..., "vehicle_type": "ambulance"}

    Two-stage dispatch:
      1. PostGIS straight-line distance narrows candidates to top 5
      2. OSRM real-road distance ranks those 5 to pick the true nearest
    Falls back to straight-line ranking if OSRM is unreachable.
    """
    serializer = DispatchRequestInputSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    lat = serializer.validated_data['lat']
    lng = serializer.validated_data['lng']
    vehicle_type = serializer.validated_data['vehicle_type']

    request_point = Point(lng, lat, srid=4326)

    # Stage 1: PostGIS straight-line pre-filter (fast, approximate)
    candidates = list(
        Vehicle.objects
        .filter(owner=request.user, is_available=True, vehicle_type=vehicle_type)
        .annotate(distance=Distance('location', request_point))
        .order_by('distance')[:5]
    )

    if not candidates:
        return Response(
            {'error': f'No available {vehicle_type} vehicles found in your organization'},
            status=status.HTTP_404_NOT_FOUND,
        )

    # Stage 2: OSRM real-road ranking on the shortlist
    ranked = []
    osrm_succeeded = False
    for v in candidates:
        distance_km, duration_min = get_route_distance(
            v.location.y, v.location.x, lat, lng
        )
        if distance_km is not None:
            osrm_succeeded = True
            ranked.append({'vehicle': v, 'distance_km': distance_km, 'duration_min': duration_min})
        else:
            # Fallback for this candidate: straight-line distance, no ETA
            ranked.append({'vehicle': v, 'distance_km': round(v.distance.km, 2), 'duration_min': None})

    ranked.sort(key=lambda x: x['distance_km'])
    best = ranked[0]
    nearest = best['vehicle']

    # Mark vehicle as unavailable
    nearest.is_available = False
    nearest.save(update_fields=['is_available'])

    # Create dispatch record with the computed distance/duration saved once
    now = timezone.now()
    dispatch = DispatchRequest.objects.create(
        request_lat=lat,
        request_lng=lng,
        vehicle_type=vehicle_type,
        assigned_vehicle=nearest,
        status='assigned',
        assigned_at=now,
        distance_km=best['distance_km'],
        duration_min=best['duration_min'],
        used_osrm=osrm_succeeded,
    )

    return Response({
        'dispatch': DispatchRequestSerializer(dispatch).data,
        'assigned_vehicle': {
            'id': nearest.id,
            'name': nearest.name,
            'lat': nearest.location.y,
            'lng': nearest.location.x,
        },
        'distance_km': best['distance_km'],
        'duration_min': best['duration_min'],
    },
    status=status.HTTP_201_CREATED)
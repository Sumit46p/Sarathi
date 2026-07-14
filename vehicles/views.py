from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance

from .models import Vehicle, DispatchRequest
from .serializers import (
    VehicleSerializer,
    LocationUpdateSerializer,
    NearestVehicleSerializer,
    DispatchRequestInputSerializer,
    DispatchRequestSerializer,
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
    vehicle.save(update_fields=['location'])

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

    Finds the nearest available vehicle of the requested type (scoped to request.user),
    marks it as unavailable, creates a DispatchRequest record, and returns the
    assigned vehicle + distance.
    """
    serializer = DispatchRequestInputSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    lat = serializer.validated_data['lat']
    lng = serializer.validated_data['lng']
    vehicle_type = serializer.validated_data['vehicle_type']

    request_point = Point(lng, lat, srid=4326)

    nearest = (
        Vehicle.objects
        .filter(owner=request.user, is_available=True, vehicle_type=vehicle_type)
        .annotate(distance=Distance('location', request_point))
        .order_by('distance')
        .first()
    )

    if nearest is None:
        return Response(
            {'error': f'No available {vehicle_type} vehicles found in your organization'},
            status=status.HTTP_404_NOT_FOUND,
        )

    # Mark vehicle as unavailable
    nearest.is_available = False
    nearest.save(update_fields=['is_available'])

    # Create dispatch record
    dispatch = DispatchRequest.objects.create(
        request_lat=lat,
        request_lng=lng,
        vehicle_type=vehicle_type,
        assigned_vehicle=nearest,
        status='assigned',
    )

    return Response({
        'dispatch': DispatchRequestSerializer(dispatch).data,
        'assigned_vehicle': {
            'id': nearest.id,
            'name': nearest.name,
            'lat': nearest.location.y,
            'lng': nearest.location.x,
        },
        'distance_km': round(nearest.distance.km, 2),
    }, status=status.HTTP_201_CREATED)

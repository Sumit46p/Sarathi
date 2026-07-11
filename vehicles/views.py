from rest_framework import generics, status
from rest_framework.decorators import api_view
from rest_framework.response import Response
from django.contrib.gis.geos import Point

from .models import Vehicle
from .serializers import VehicleSerializer, LocationUpdateSerializer


class VehicleListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/vehicles/      — list all vehicles with current location
    POST /api/vehicles/      — create a new vehicle (for testing without admin)
    """
    queryset = Vehicle.objects.all()
    serializer_class = VehicleSerializer


class VehicleDetailView(generics.RetrieveAPIView):
    """
    GET /api/vehicles/<id>/  — detail of one vehicle
    """
    queryset = Vehicle.objects.all()
    serializer_class = VehicleSerializer


@api_view(['POST'])
def update_location(request, pk):
    """
    POST /api/vehicles/<id>/update-location/
    Body: {"lat": 26.54, "lng": 87.89}

    Updates the vehicle's GPS location and returns the updated vehicle.
    This endpoint is called by the Flutter driver app (or the simulator script).
    """
    try:
        vehicle = Vehicle.objects.get(pk=pk)
    except Vehicle.DoesNotExist:
        return Response(
            {'error': f'Vehicle {pk} not found'},
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

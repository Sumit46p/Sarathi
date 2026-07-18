from rest_framework import serializers
from django.contrib.gis.geos import Point
from .models import Vehicle, DispatchRequest, Driver, MaintenanceRecord


class LocationField(serializers.Field):
    """
    Serializes a PointField to/from plain {"lat": ..., "lng": ...} JSON.
    Internally Django stores Point(lng, lat) — note the order — but the
    API exposes the more intuitive {"lat": ..., "lng": ...} format.
    """

    def to_representation(self, value):
        if value is None:
            return None
        return {'lat': value.y, 'lng': value.x}

    def to_internal_value(self, data):
        if data is None:
            return None
        try:
            lat = float(data['lat'])
            lng = float(data['lng'])
        except (KeyError, TypeError, ValueError):
            raise serializers.ValidationError(
                'Location must be {"lat": <number>, "lng": <number>}'
            )
        if not (-90 <= lat <= 90):
            raise serializers.ValidationError('lat must be between -90 and 90')
        if not (-180 <= lng <= 180):
            raise serializers.ValidationError('lng must be between -180 and 180')
        return Point(lng, lat, srid=4326)


class DriverSerializer(serializers.ModelSerializer):
    class Meta:
        model = Driver
        fields = ['id', 'name', 'phone_number', 'license_number', 'is_active']
        read_only_fields = ['id']


class VehicleSerializer(serializers.ModelSerializer):
    location = LocationField()
    driver_name = serializers.CharField(source='driver.name', read_only=True, default=None)

    class Meta:
        model = Vehicle
        fields = ['id', 'name', 'vehicle_type', 'number_plate', 'is_available', 'location', 'driver', 'driver_name']
        read_only_fields = ['id', 'driver_name']


class LocationUpdateSerializer(serializers.Serializer):
    """Accepts just {"lat": ..., "lng": ...} for the update-location endpoint."""
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)


class NearestVehicleSerializer(serializers.Serializer):
    """Read-only serializer for nearest-vehicle search results."""
    id = serializers.IntegerField()
    name = serializers.CharField()
    distance_km = serializers.FloatField()
    lat = serializers.FloatField()
    lng = serializers.FloatField()


class DispatchRequestInputSerializer(serializers.Serializer):
    """Validates incoming dispatch requests."""
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    vehicle_type = serializers.ChoiceField(choices=Vehicle.VEHICLE_TYPE_CHOICES)


class AssignDriverSerializer(serializers.Serializer):
    """Validates driver assignment payload."""
    driver_id = serializers.IntegerField(allow_null=True, required=False)


class DispatchRequestSerializer(serializers.ModelSerializer):
    assigned_vehicle_name = serializers.CharField(
        source='assigned_vehicle.name', read_only=True, default=None
    )
    response_time_seconds = serializers.FloatField(read_only=True)
    trip_duration_seconds = serializers.FloatField(read_only=True)

    class Meta:
        model = DispatchRequest
        fields = [
            'id',
            'request_lat', 'request_lng',
            'vehicle_type',
            'assigned_vehicle', 'assigned_vehicle_name',
            'status',
            'created_at', 'assigned_at', 'accepted_at',
            'en_route_at', 'arrived_at', 'completed_at',
            'response_time_seconds', 'trip_duration_seconds',
            'distance_km', 'duration_min', 'used_osrm',   # ← added
        ]
        read_only_fields = fields


class MaintenanceRecordSerializer(serializers.ModelSerializer):
    """Serializer for vehicle maintenance records."""
    vehicle_name = serializers.CharField(source='vehicle.name', read_only=True)

    class Meta:
        model = MaintenanceRecord
        fields = ['id', 'vehicle', 'vehicle_name', 'service_type', 'service_date', 'notes', 'next_service_due', 'owner']
        read_only_fields = ['id', 'vehicle_name', 'owner']
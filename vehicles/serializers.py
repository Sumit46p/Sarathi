from rest_framework import serializers
from django.contrib.gis.geos import Point
from .models import Vehicle


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


class VehicleSerializer(serializers.ModelSerializer):
    location = LocationField()

    class Meta:
        model = Vehicle
        fields = ['id', 'name', 'vehicle_type', 'is_available', 'location']
        read_only_fields = ['id']


class LocationUpdateSerializer(serializers.Serializer):
    """Accepts just {"lat": ..., "lng": ...} for the update-location endpoint."""
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)

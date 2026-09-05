from rest_framework import serializers
import json
from django.contrib.gis.geos import Point
from django.contrib.auth.models import User
from accounts.models import Profile, get_organization_name
from .models import (
    Vehicle, Driver, DispatchRequest, MaintenanceRecord, MaintenanceTemplate,
    IssueReport, Notification, EmergencyRequest, FuelEntry, FuelLog, FuelPrice,
    OperationalLocation
)

class PointDictField(serializers.Field):
    """
    A custom field that serializes a GEOS Point to a dict {"lat": y, "lng": x}
    and deserializes a dict or JSON string to a GEOS Point.
    """
    def to_representation(self, value):
        if value:
            return {'lat': value.y, 'lng': value.x}
        return None

    def to_internal_value(self, data):
        if isinstance(data, str):
            try:
                data = json.loads(data)
            except Exception:
                raise serializers.ValidationError("Invalid JSON format for location.")
        if not isinstance(data, dict):
            raise serializers.ValidationError("Location must be a dictionary or valid JSON string.")
        
        try:
            lat = float(data.get('lat'))
            lng = float(data.get('lng'))
            return Point(lng, lat, srid=4326)
        except (TypeError, ValueError, AttributeError):
            raise serializers.ValidationError("Invalid location format. Expected {'lat': float, 'lng': float}")


class DriverSerializer(serializers.ModelSerializer):
    username = serializers.CharField(write_only=True, required=False, allow_blank=True)
    password = serializers.CharField(write_only=True, required=False, allow_blank=True)
    user_username = serializers.CharField(source='user.username', read_only=True, default=None)

    class Meta:
        model = Driver
        fields = [
            'id', 'name', 'phone_number', 'license_number', 'is_active', 'is_on_duty',
            'requires_password_change', 'user', 'username', 'password', 'user_username'
        ]
        read_only_fields = ['id', 'user', 'user_username']

    def validate_username(self, value):
        if value:
            value = value.strip()
            if self.instance and self.instance.user and self.instance.user.username == value:
                return value
            if User.objects.filter(username=value).exists():
                raise serializers.ValidationError("A user with this username already exists.")
        return value

    def create(self, validated_data):
        username = (validated_data.pop('username', None) or '').strip()
        password = validated_data.pop('password', None)

        user = None
        if username and password:
            user = User.objects.create_user(username=username, password=password)
            org_name = self.context.get('organization_name') or get_organization_name()
            profile, _ = Profile.objects.get_or_create(user=user)
            profile.role = 'DRIVER'
            profile.organization_name = org_name
            profile.save()

        validated_data['user'] = user
        return super().create(validated_data)

    def update(self, instance, validated_data):
        username = (validated_data.pop('username', None) or '').strip()
        password = validated_data.pop('password', None)

        if instance.user:
            if username and username != instance.user.username:
                if User.objects.filter(username=username).exclude(id=instance.user.id).exists():
                    raise serializers.ValidationError({"username": "A user with this username already exists."})
                instance.user.username = username
                instance.user.save()
            if password:
                instance.user.set_password(password)
                instance.user.save()
        elif username and password:
            user = User.objects.create_user(username=username, password=password)
            org_name = self.context.get('organization_name') or get_organization_name()
            profile, _ = Profile.objects.get_or_create(user=user)
            profile.role = 'DRIVER'
            profile.organization_name = org_name
            profile.save()
            instance.user = user
            instance.save()

        return super().update(instance, validated_data)

class VehicleSerializer(serializers.ModelSerializer):
    driver_name = serializers.SerializerMethodField()
    location = PointDictField()
    photo_url = serializers.SerializerMethodField()
    
    def get_driver_name(self, obj):
        return obj.driver.name if obj.driver else None
    
    def get_photo_url(self, obj):
        if obj.photo and obj.photo.name:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.photo.url)
            return obj.photo.url
        return None

    class Meta:
        model = Vehicle
        fields = [
            'id', 'name', 'vehicle_type', 'fuel_type', 'number_plate',
            'is_available', 'admin_blocked', 'location',
            'photo', 'photo_url',
            'driver', 'driver_name', 'last_location_at',
            'total_distance_km',
            'has_active_dispatch', 'active_dispatch_status',
        ]
        read_only_fields = [
            'id', 'driver_name', 'is_available', 'photo_url',
            'has_active_dispatch', 'active_dispatch_status',
            'last_location_at', 'total_distance_km',
        ]

class LocationUpdateSerializer(serializers.Serializer):
    """Accepts {"lat": ..., "lng": ..., "speed_kmh": ...} for the update-location endpoint."""
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    speed_kmh = serializers.FloatField(required=False, min_value=0)

class AssignDriverSerializer(serializers.Serializer):
    """Accepts {"driver_id": 5} or {"driver_id": null}."""
    driver_id = serializers.IntegerField(required=False, allow_null=True)

class OperationalLocationSerializer(serializers.ModelSerializer):
    lat = serializers.SerializerMethodField()
    lng = serializers.SerializerMethodField()

    def get_lat(self, obj):
        return obj.location.y if obj.location else None

    def get_lng(self, obj):
        return obj.location.x if obj.location else None

    class Meta:
        model = OperationalLocation
        fields = [
            'id', 'name', 'category', 'address', 'lat', 'lng',
            'contact_phone', 'is_active'
        ]


class DispatchRequestSerializer(serializers.ModelSerializer):
    assigned_vehicle_name = serializers.SerializerMethodField()
    assigned_vehicle_plate = serializers.SerializerMethodField()
    assigned_driver_name = serializers.SerializerMethodField()
    assigned_driver_phone = serializers.SerializerMethodField()
    assigned_vehicle_photo = serializers.SerializerMethodField()
    failed_vehicle_name = serializers.SerializerMethodField()
    failed_vehicle_plate = serializers.SerializerMethodField()

    def get_assigned_vehicle_name(self, obj):
        return obj.assigned_vehicle.name if obj.assigned_vehicle else None

    def get_assigned_vehicle_plate(self, obj):
        return obj.assigned_vehicle.number_plate if obj.assigned_vehicle else None

    def get_assigned_driver_name(self, obj):
        if obj.assigned_vehicle and obj.assigned_vehicle.driver:
            return obj.assigned_vehicle.driver.name
        return None

    def get_assigned_driver_phone(self, obj):
        if obj.assigned_vehicle and obj.assigned_vehicle.driver:
            return obj.assigned_vehicle.driver.phone_number
        return None

    def get_assigned_vehicle_photo(self, obj):
        if obj.assigned_vehicle and obj.assigned_vehicle.photo:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.assigned_vehicle.photo.url)
            return obj.assigned_vehicle.photo.url
        return None

    def get_failed_vehicle_name(self, obj):
        return obj.failed_vehicle.name if obj.failed_vehicle else None

    def get_failed_vehicle_plate(self, obj):
        return obj.failed_vehicle.number_plate if obj.failed_vehicle else None

    class Meta:
        model = DispatchRequest
        fields = [
            'id', 'operation_type', 'request_type', 'priority', 'request_lat', 'request_lng',
            'location_name', 'address', 'access_lat', 'access_lng',
            'dest_lat', 'dest_lng', 'destination_name', 'destination_address',
            'cargo_description', 'cargo_weight_kg',
            'original_dispatch', 'failed_vehicle', 'failed_vehicle_name', 'failed_vehicle_plate',
            'breakdown_reason',
            'vehicle_type', 'assigned_vehicle', 'assigned_vehicle_name',
            'assigned_vehicle_plate', 'assigned_driver_name', 'assigned_driver_phone',
            'assigned_vehicle_photo', 'status', 'selection_reason',
            'distance_km', 'duration_min', 'used_osrm',
            'created_by', 'created_at', 'assigned_at', 'accepted_at',
            'en_route_at', 'arrived_at', 'in_service_at', 'completed_at',
        ]

class MaintenanceRecordSerializer(serializers.ModelSerializer):
    vehicle_name = serializers.SerializerMethodField()
    image_url = serializers.SerializerMethodField()
    proof_image_url = serializers.SerializerMethodField()

    def get_vehicle_name(self, obj):
        return obj.vehicle.name if obj.vehicle else None

    def get_image_url(self, obj):
        if obj.image and obj.image.name:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.image.url)
            return obj.image.url
        return None

    def get_proof_image_url(self, obj):
        if obj.proof_image and obj.proof_image.name:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.proof_image.url)
            return obj.proof_image.url
        return None

    class Meta:
        model = MaintenanceRecord
        fields = [
            'id', 'vehicle', 'vehicle_name', 'maintenance_type', 'description',
            'due_date', 'completed', 'completed_at', 'recurrence_days',
            'recurrence_km', 'image', 'image_url', 'proof_image', 'proof_image_url',
            'completed_by', 'completion_notes', 'cost'
        ]

class MaintenanceTemplateSerializer(serializers.ModelSerializer):
    class Meta:
        model = MaintenanceTemplate
        fields = ['id', 'name', 'maintenance_type', 'description', 'recurrence_days', 'recurrence_km']

class IssueReportSerializer(serializers.ModelSerializer):
    driver_name = serializers.SerializerMethodField()
    vehicle_name = serializers.SerializerMethodField()
    image_url = serializers.SerializerMethodField()

    def get_driver_name(self, obj):
        return obj.driver.name

    def get_vehicle_name(self, obj):
        vehicle = obj.driver.assigned_vehicles.first()
        return vehicle.name if vehicle else "Unassigned"

    def get_image_url(self, obj):
        if obj.image and obj.image.name:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.image.url)
            return obj.image.url
        return None

    class Meta:
        model = IssueReport
        fields = ['id', 'driver', 'driver_name', 'vehicle_name', 'description', 'image', 'image_url', 'status', 'created_at']
        read_only_fields = ['id', 'driver', 'created_at']

class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ['id', 'title', 'message', 'notification_type', 'is_read', 'created_at']

class EmergencyRequestSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()
    driver_vehicle_name = serializers.SerializerMethodField()
    driver_vehicle_id = serializers.SerializerMethodField()
    driver_vehicle_plate = serializers.SerializerMethodField()
    driver_name = serializers.SerializerMethodField()
    driver_phone = serializers.SerializerMethodField()
    location = serializers.SerializerMethodField()
    related_dispatch_details = serializers.SerializerMethodField()

    def get_image_url(self, obj):
        if obj.image and obj.image.name:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.image.url)
            return obj.image.url
        return None

    def get_driver_vehicle_name(self, obj):
        if obj.assigned_vehicle:
            return obj.assigned_vehicle.name
        if obj.user:
            try:
                driver = Driver.objects.filter(user=obj.user).first()
                if driver:
                    vehicle = driver.assigned_vehicles.first()
                    return vehicle.name if vehicle else None
            except Exception:
                pass
        return None

    def get_driver_vehicle_id(self, obj):
        if obj.assigned_vehicle:
            return obj.assigned_vehicle.id
        if obj.user:
            try:
                driver = Driver.objects.filter(user=obj.user).first()
                if driver:
                    vehicle = driver.assigned_vehicles.first()
                    return vehicle.id if vehicle else None
            except Exception:
                pass
        return None

    def get_driver_vehicle_plate(self, obj):
        if obj.assigned_vehicle:
            return obj.assigned_vehicle.number_plate
        if obj.user:
            try:
                driver = Driver.objects.filter(user=obj.user).first()
                if driver:
                    vehicle = driver.assigned_vehicles.first()
                    return vehicle.number_plate if vehicle else None
            except Exception:
                pass
        return None

    def get_driver_name(self, obj):
        if obj.assigned_vehicle and obj.assigned_vehicle.driver:
            return obj.assigned_vehicle.driver.name
        if obj.user:
            try:
                driver = Driver.objects.filter(user=obj.user).first()
                if driver:
                    return driver.name
                return obj.user.get_full_name() or obj.user.username
            except Exception:
                return obj.user.username if hasattr(obj.user, 'username') else 'Unknown'
        return 'Fleet Driver'

    def get_driver_phone(self, obj):
        if obj.assigned_vehicle and obj.assigned_vehicle.driver:
            return obj.assigned_vehicle.driver.phone_number
        if obj.user:
            try:
                driver = Driver.objects.filter(user=obj.user).first()
                return driver.phone_number if driver else None
            except Exception:
                return None
        return None

    def get_location(self, obj):
        if obj.location:
            return {'lat': obj.location.y, 'lng': obj.location.x}
        return None

    def get_related_dispatch_details(self, obj):
        if obj.related_dispatch:
            disp = obj.related_dispatch
            return {
                'id': disp.id,
                'location_name': disp.location_name,
                'address': disp.address,
                'pickup_lat': disp.request_lat,
                'pickup_lng': disp.request_lng,
                'destination_name': disp.destination_name,
                'destination_address': disp.destination_address,
                'dest_lat': disp.dest_lat,
                'dest_lng': disp.dest_lng,
                'cargo_description': disp.cargo_description,
                'cargo_weight_kg': disp.cargo_weight_kg,
                'status': disp.status,
            }
        return None

    class Meta:
        model = EmergencyRequest
        fields = [
            'id', 'user', 'emergency_type', 'description', 'location',
            'image', 'image_url', 'driver_vehicle_name', 'driver_vehicle_id',
            'driver_vehicle_plate', 'driver_name', 'driver_phone', 'status',
            'assigned_vehicle', 'related_dispatch', 'replacement_dispatch',
            'related_dispatch_details',
            'created_at', 'updated_at', 'resolved_at'
        ]

class FuelEntrySerializer(serializers.ModelSerializer):
    driver_name = serializers.SerializerMethodField()
    vehicle_name = serializers.SerializerMethodField()

    def get_driver_name(self, obj):
        return obj.driver.name

    def get_vehicle_name(self, obj):
        return obj.vehicle.name

    class Meta:
        model = FuelEntry
        fields = [
            'id', 'vehicle', 'vehicle_name', 'driver', 'driver_name',
            'liters', 'cost_per_liter', 'total_cost', 'odometer_km',
            'notes', 'fueled_at', 'created_at'
        ]
        read_only_fields = ['id', 'created_at']

class FuelLogSerializer(serializers.ModelSerializer):
    driver_name = serializers.SerializerMethodField()
    vehicle_name = serializers.SerializerMethodField()
    receipt_image_url = serializers.SerializerMethodField()

    def get_driver_name(self, obj):
        return obj.driver.name

    def get_vehicle_name(self, obj):
        return obj.vehicle.name

    def get_receipt_image_url(self, obj):
        if obj.receipt_image and obj.receipt_image.name:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.receipt_image.url)
            return obj.receipt_image.url
        return None

    class Meta:
        model = FuelLog
        fields = [
            'id', 'vehicle', 'vehicle_name', 'driver', 'driver_name',
            'fuel_type', 'liters', 'amount', 'cost_per_liter',
            'odometer_reading', 'receipt_image_url', 'notes', 'created_at'
        ]
        read_only_fields = ['id', 'created_at']

class FuelPriceSerializer(serializers.ModelSerializer):
    class Meta:
        model = FuelPrice
        fields = ['id', 'fuel_type', 'price_per_liter', 'last_updated', 'source']
        read_only_fields = ['id', 'fuel_type', 'price_per_liter', 'last_updated', 'source']

class NearestVehicleSerializer(serializers.Serializer):
    """Response for nearest vehicle query."""
    vehicle_id = serializers.IntegerField()
    vehicle_name = serializers.CharField()
    distance_km = serializers.DecimalField(max_digits=8, decimal_places=2)
    duration_min = serializers.IntegerField()
    lat = serializers.FloatField()
    lng = serializers.FloatField()

class DispatchRequestInputSerializer(serializers.Serializer):
    """Input for creating dispatch requests."""
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    vehicle_type = serializers.CharField(max_length=20)

class DriverAssignedVehicleSerializer(serializers.ModelSerializer):
    """Simplified vehicle serializer for driver's assigned vehicle (no PostGIS fields)."""
    class Meta:
        model = Vehicle
        fields = ['id', 'name', 'vehicle_type', 'number_plate', 'is_available']

class DriverMeSerializer(serializers.ModelSerializer):
    assigned_vehicle = DriverAssignedVehicleSerializer(read_only=True)

    class Meta:
        model = Driver
        fields = [
            'id', 'name', 'phone_number', 'license_number', 'is_active',
            'is_on_duty', 'requires_password_change', 'assigned_vehicle'
        ]

class EmergencyRequestCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = EmergencyRequest
        fields = ['emergency_type', 'description', 'location', 'image']

class FuelLogCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = FuelLog
        fields = ['vehicle', 'fuel_type', 'liters', 'amount', 'cost_per_liter', 'odometer_reading', 'receipt_image', 'notes']

class ExpenseStatsSerializer(serializers.Serializer):
    """Aggregated expense statistics."""
    total_fuel_cost = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_maintenance_cost = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_operational_cost = serializers.DecimalField(max_digits=12, decimal_places=2)
    fuel_entries_count = serializers.IntegerField()
    maintenance_records_count = serializers.IntegerField()
    average_fuel_cost_per_liter = serializers.DecimalField(max_digits=8, decimal_places=2)
    by_vehicle = serializers.ListField(child=serializers.DictField())
    by_driver = serializers.ListField(child=serializers.DictField())

from rest_framework import serializers
from .models import (
    Vehicle, Driver, DispatchRequest, MaintenanceRecord, MaintenanceTemplate,
    IssueReport, Notification, EmergencyRequest, FuelEntry, FuelLog, FuelPrice
)

class DriverSerializer(serializers.ModelSerializer):
    class Meta:
        model = Driver
        fields = ['id', 'name', 'phone_number', 'license_number', 'is_active', 'is_on_duty', 'user']
        read_only_fields = ['id', 'user']

class VehicleSerializer(serializers.ModelSerializer):
    driver_name = serializers.SerializerMethodField()
    location = serializers.SerializerMethodField()
    
    def get_driver_name(self, obj):
        return obj.driver.name if obj.driver else None
    
    def get_location(self, obj):
        if obj.location:
            return {'lat': obj.location.y, 'lng': obj.location.x}
        return None

    class Meta:
        model = Vehicle
        fields = [
            'id', 'name', 'vehicle_type', 'number_plate',
            'is_available', 'admin_blocked', 'location',
            'driver', 'driver_name', 'last_location_at',
            'total_distance_km',
            'has_active_dispatch', 'active_dispatch_status',
        ]
        read_only_fields = [
            'id', 'driver_name', 'is_available',
            'has_active_dispatch', 'active_dispatch_status',
            'last_location_at', 'total_distance_km',
        ]

class LocationUpdateSerializer(serializers.Serializer):
    """Accepts just {"lat": ..., "lng": ...} for the update-location endpoint."""
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)

class AssignDriverSerializer(serializers.Serializer):
    """Accepts {"driver_id": 5} or {"driver_id": null}."""
    driver_id = serializers.IntegerField(required=False, allow_null=True)

class DispatchRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = DispatchRequest
        fields = [
            'id', 'request_lat', 'request_lng', 'vehicle_type',
            'assigned_vehicle', 'status', 'distance_km', 'duration_min',
            'used_osrm', 'created_at', 'assigned_at', 'accepted_at',
            'en_route_at', 'arrived_at', 'completed_at'
        ]

class MaintenanceRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = MaintenanceRecord
        fields = [
            'id', 'vehicle', 'maintenance_type', 'description',
            'due_date', 'completed', 'completed_at', 'recurrence_days',
            'recurrence_km', 'image', 'proof_image', 'completed_by',
            'completion_notes', 'cost'
        ]

class MaintenanceTemplateSerializer(serializers.ModelSerializer):
    class Meta:
        model = MaintenanceTemplate
        fields = ['id', 'name', 'maintenance_type', 'description', 'recurrence_days', 'recurrence_km']

class IssueReportSerializer(serializers.ModelSerializer):
    driver_name = serializers.SerializerMethodField()

    def get_driver_name(self, obj):
        return obj.driver.name

    class Meta:
        model = IssueReport
        fields = ['id', 'driver', 'driver_name', 'description', 'image', 'status', 'created_at']
        read_only_fields = ['id', 'driver', 'created_at']

class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ['id', 'title', 'message', 'notification_type', 'is_read', 'created_at']

class EmergencyRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = EmergencyRequest
        fields = [
            'id', 'user', 'emergency_type', 'description', 'location',
            'image', 'status', 'assigned_vehicle', 'created_at', 'updated_at',
            'resolved_at'
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
        fields = ['id', 'name', 'phone_number', 'license_number', 'is_on_duty', 'assigned_vehicle']

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

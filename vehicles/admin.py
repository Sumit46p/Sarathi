from django.contrib.gis import admin
from .models import Vehicle, DispatchRequest


@admin.register(Vehicle)
class VehicleAdmin(admin.GISModelAdmin):
    """Admin interface for Vehicle with an interactive map picker for location."""

    list_display = ('name', 'vehicle_type', 'is_available')
    list_filter = ('vehicle_type', 'is_available')
    search_fields = ('name',)


@admin.register(DispatchRequest)
class DispatchRequestAdmin(admin.ModelAdmin):
    """Admin interface for dispatch request records."""

    list_display = ('id', 'vehicle_type', 'status', 'assigned_vehicle', 'created_at')
    list_filter = ('status', 'vehicle_type')
    readonly_fields = ('created_at',)

from django.contrib.gis import admin
from .models import Vehicle


@admin.register(Vehicle)
class VehicleAdmin(admin.GISModelAdmin):
    """Admin interface for Vehicle with an interactive map picker for location."""

    list_display = ('name', 'vehicle_type', 'is_available')
    list_filter = ('vehicle_type', 'is_available')
    search_fields = ('name',)

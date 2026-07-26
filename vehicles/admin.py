from django.contrib.gis import admin
from .models import Vehicle, DispatchRequest, IssueReport, Driver


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


@admin.register(IssueReport)
class IssueReportAdmin(admin.ModelAdmin):
    """Admin interface for driver issue reports."""

    list_display = ('id', 'driver', 'status', 'created_at')
    list_filter = ('status', 'created_at')
    search_fields = ('driver__name', 'description')
    readonly_fields = ('created_at',)
@admin.register(Driver)
class DriverAdmin(admin.ModelAdmin):
    list_display = ('name', 'phone_number', 'license_number', 'is_active', 'is_on_duty')
    search_fields = ('name', 'license_number')

    def delete_model(self, request, obj):
        user = obj.user
        super().delete_model(request, obj)
        if user:
            user.delete()

    def delete_queryset(self, request, queryset):
        users = [obj.user for obj in queryset if obj.user]
        super().delete_queryset(request, queryset)
        for user in users:
            user.delete()

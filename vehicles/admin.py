from django.contrib.gis import admin
from .models import Vehicle, DispatchRequest, IssueReport, Driver, Notification, EmergencyRequest, MaintenanceRecord, MaintenanceTemplate


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


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    """Admin interface for notifications."""
    list_display = ('id', 'user', 'notification_type', 'title', 'is_read', 'created_at')
    list_filter = ('notification_type', 'is_read', 'created_at')
    search_fields = ('user__username', 'title', 'message')
    readonly_fields = ('created_at',)
    list_editable = ('is_read',)


@admin.register(EmergencyRequest)
class EmergencyRequestAdmin(admin.ModelAdmin):
    """Admin interface for emergency requests."""
    list_display = ('id', 'user', 'emergency_type', 'status', 'assigned_vehicle', 'created_at')
    list_filter = ('emergency_type', 'status', 'created_at')
    search_fields = ('user__username', 'description')
    readonly_fields = ('created_at', 'updated_at', 'resolved_at')


@admin.register(MaintenanceRecord)
class MaintenanceRecordAdmin(admin.ModelAdmin):
    """Admin interface for maintenance records."""
    list_display = ('id', 'vehicle', 'maintenance_type', 'due_date', 'completed', 'owner')
    list_filter = ('maintenance_type', 'completed', 'due_date')
    search_fields = ('vehicle__name', 'description')
    readonly_fields = ('completed_at',)


@admin.register(MaintenanceTemplate)
class MaintenanceTemplateAdmin(admin.ModelAdmin):
    """Admin interface for maintenance templates."""
    list_display = ('id', 'name', 'maintenance_type', 'recurrence_days', 'recurrence_km', 'owner')
    list_filter = ('maintenance_type',)
    search_fields = ('name', 'description')
    readonly_fields = ('created_at',)


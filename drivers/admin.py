from django.contrib import admin
from .models import DriverProfile, DriverDocument, LoginEvent


@admin.register(DriverProfile)
class DriverProfileAdmin(admin.ModelAdmin):
    list_display = ['name', 'email', 'phone', 'vehicle_number', 'department', 'status', 'created_at']
    list_filter = ['status', 'department']
    search_fields = ['name', 'email', 'phone', 'vehicle_number', 'firebase_uid']
    readonly_fields = ['firebase_uid', 'created_at', 'updated_at']
    ordering = ['-created_at']


@admin.register(DriverDocument)
class DriverDocumentAdmin(admin.ModelAdmin):
    list_display = ['driver', 'doc_type', 'file_name', 'uploaded_at']
    list_filter = ['doc_type']
    search_fields = ['driver__name', 'driver__email', 'file_name']
    readonly_fields = ['uploaded_at']
    ordering = ['-uploaded_at']


@admin.register(LoginEvent)
class LoginEventAdmin(admin.ModelAdmin):
    list_display = ['email', 'firebase_uid', 'logged_in_at']
    search_fields = ['email', 'firebase_uid']
    readonly_fields = ['logged_in_at']
    ordering = ['-logged_in_at']

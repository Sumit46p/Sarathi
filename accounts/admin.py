from django.contrib import admin
from .models import Profile, Organization

@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'role', 'organization_name')
    list_filter = ('role', 'organization_name')
    search_fields = ('user__username', 'organization_name')

@admin.register(Organization)
class OrganizationAdmin(admin.ModelAdmin):
    list_display = ('name', 'organization_type', 'status')

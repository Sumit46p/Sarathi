from django.utils.decorators import decorator_from_middleware
from django.utils import timezone
from django.contrib.auth.models import AnonymousUser

class DriverActivityMiddleware:
    """Middleware that updates last_app_activity on every authenticated API request from a driver.
    
    This ensures that when a driver's app is active and making API calls, we track
    their activity timestamp. If the app goes inactive (no requests for 5+ minutes),
    the driver is marked as unavailable automatically via the Profile.is_online property.
    """
    
    def __init__(self, get_response):
        self.get_response = get_response
    
    def __call__(self, request):
        response = self.get_response(request)
        
        # Only track authenticated driver requests (exclude admin/dispatch portal requests)
        if request.user and not isinstance(request.user, AnonymousUser):
            # Check if this is a driver (has a driver_profile relationship)
            if hasattr(request.user, 'driver_profile'):
                # Update the profile's last_app_activity timestamp
                profile = request.user.profile
                if profile:
                    profile.last_app_activity = timezone.now()
                    profile.save(update_fields=['last_app_activity'])
        
        return response
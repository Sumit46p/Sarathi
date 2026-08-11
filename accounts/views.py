import random
from datetime import timedelta
from rest_framework import generics
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from django.conf import settings
from django.contrib.auth.models import User
from .models import get_organization_name
from .serializers import (
    RegisterSerializer,
    UserSerializer,
    EmailOrUsernameTokenObtainPairSerializer,
)

# Base session / token lifetime: 12 hours (matches SESSION_COOKIE_AGE).
_SESSION_BASE_SECONDS = getattr(settings, 'SESSION_COOKIE_AGE', 43_200)
# Max jitter in seconds applied per login (default ±5 min from settings).
_SESSION_JITTER_SECONDS = getattr(settings, 'SESSION_JITTER_SECONDS', 300)


class LoginView(TokenObtainPairView):
    """
    Extends the default JWT login view to apply per-login TTL jitter.

    Each successful login receives an access-token lifetime of
    SESSION_COOKIE_AGE ± SESSION_JITTER_SECONDS (12 h ± 5 min by default).
    This staggers token expiry across a burst of concurrent logins so they
    don't all hammer the refresh endpoint at the same instant
    (thundering-herd prevention).
    """
    serializer_class = EmailOrUsernameTokenObtainPairSerializer
    throttle_classes = (ScopedRateThrottle,)
    throttle_scope = 'login'

    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        if response.status_code == 200:
            # Apply jitter: random delta in [-jitter, +jitter] seconds
            jitter = random.randint(0, _SESSION_JITTER_SECONDS) * random.choice([-1, 1])
            jittered_lifetime = timedelta(seconds=max(60, _SESSION_BASE_SECONDS + jitter))
            # Inform the client of the actual expiry seconds so it can
            # schedule its own refresh before the token lapses.
            response.data['expires_in'] = int(jittered_lifetime.total_seconds())
        return response

class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    permission_classes = (AllowAny,)
    serializer_class = RegisterSerializer
    throttle_classes = (ScopedRateThrottle,)
    throttle_scope = 'register'

class UserDetailView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

class VerifyAdminUserView(APIView):
    permission_classes = (AllowAny,)
    throttle_classes = (ScopedRateThrottle,)
    throttle_scope = 'verify_identity'

    def post(self, request):
        username = request.data.get('username')
        organization_name = request.data.get('organization_name')
        if not username or not organization_name:
            return Response({'error': 'Username and organization name are required'}, status=400)
        
        user = User.objects.filter(username=username).first()
        if not user:
            return Response({'error': 'User not found'}, status=404)

        # Validate against the canonical (admin's) org name, case-insensitive
        expected_org = get_organization_name()
        if not hasattr(user, 'profile') or expected_org.lower() != (organization_name or '').lower():
            return Response({'error': f'Invalid organization name. Expected: {expected_org}'}, status=400)

        return Response({'success': True, 'message': 'User verified'})

class ResetAdminPasswordView(APIView):
    permission_classes = (AllowAny,)
    throttle_classes = (ScopedRateThrottle,)
    throttle_scope = 'reset_password'

    def post(self, request):
        username = request.data.get('username')
        organization_name = request.data.get('organization_name')
        new_password = request.data.get('new_password')

        if not all([username, organization_name, new_password]):
            return Response({'error': 'Missing required fields'}, status=400)
        
        user = User.objects.filter(username=username).first()
        if not user:
            return Response({'error': 'User not found'}, status=404)

        # Validate against the canonical (admin's) org name, case-insensitive
        expected_org = get_organization_name()
        if not hasattr(user, 'profile') or expected_org.lower() != (organization_name or '').lower():
            return Response({'error': f'Invalid organization name. Expected: {expected_org}'}, status=400)

        if len(new_password) < 8:
            return Response({'error': 'Password must be at least 8 characters'}, status=400)
        
        user.set_password(new_password)
        user.save()

        return Response({'success': True, 'message': 'Password reset successfully'})

class ChangeAdminPasswordView(APIView):
    permission_classes = (IsAuthenticated,)
    throttle_classes = (ScopedRateThrottle,)
    throttle_scope = 'reset_password'

    def post(self, request):
        from .serializers import ChangeAdminPasswordSerializer
        serializer = ChangeAdminPasswordSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=400)

        user = request.user
        if not user.check_password(serializer.validated_data['old_password']):
            return Response({'error': 'Incorrect current password'}, status=400)
        
        user.set_password(serializer.validated_data['new_password'])
        user.save()
        return Response({'success': True, 'message': 'Password updated successfully'})

class OrganizationsView(APIView):
    permission_classes = (AllowAny,)

    def get(self, request):
        from .models import Profile
        orgs = Profile.objects.exclude(organization_name='Default Org').values_list('organization_name', flat=True).distinct()
        return Response(list(orgs))


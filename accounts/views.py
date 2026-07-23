from rest_framework import generics
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from django.contrib.auth.models import User
from .serializers import (
    RegisterSerializer,
    UserSerializer,
    EmailOrUsernameTokenObtainPairSerializer,
)

class LoginView(TokenObtainPairView):
    serializer_class = EmailOrUsernameTokenObtainPairSerializer

class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    permission_classes = (AllowAny,)
    serializer_class = RegisterSerializer

class UserDetailView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

class VerifyAdminUserView(APIView):
    permission_classes = (AllowAny,)

    def post(self, request):
        username = request.data.get('username')
        organization_name = request.data.get('organization_name')
        if not username or not organization_name:
            return Response({'error': 'Username and organization name are required'}, status=400)
        
        user = User.objects.filter(username=username).first()
        if not user:
            return Response({'error': 'User not found'}, status=404)
        
        if not hasattr(user, 'profile') or user.profile.organization_name != organization_name:
            return Response({'error': 'Invalid organization name'}, status=400)
        
        return Response({'success': True, 'message': 'User verified'})

class ResetAdminPasswordView(APIView):
    permission_classes = (AllowAny,)

    def post(self, request):
        username = request.data.get('username')
        organization_name = request.data.get('organization_name')
        new_password = request.data.get('new_password')

        if not all([username, organization_name, new_password]):
            return Response({'error': 'Missing required fields'}, status=400)
        
        user = User.objects.filter(username=username).first()
        if not user:
            return Response({'error': 'User not found'}, status=404)
        
        if not hasattr(user, 'profile') or user.profile.organization_name != organization_name:
            return Response({'error': 'Invalid organization name'}, status=400)
        
        if len(new_password) < 8:
            return Response({'error': 'Password must be at least 8 characters'}, status=400)
        
        user.set_password(new_password)
        user.save()

        return Response({'success': True, 'message': 'Password reset successfully'})

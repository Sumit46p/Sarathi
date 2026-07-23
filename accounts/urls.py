from django.urls import path
from rest_framework_simplejwt.views import (
    TokenRefreshView,
)
from .views import LoginView, RegisterView, UserDetailView, VerifyAdminUserView, ResetAdminPasswordView

urlpatterns = [
    path('login/', LoginView.as_view(), name='token_obtain_pair'),
    path('login/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('register/', RegisterView.as_view(), name='register'),
    path('me/', UserDetailView.as_view(), name='user_detail'),
    path('verify-admin/', VerifyAdminUserView.as_view(), name='verify_admin'),
    path('reset-admin-password/', ResetAdminPasswordView.as_view(), name='reset_admin_password'),
]

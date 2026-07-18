from django.urls import path
from .views import (
    DriverRegisterView,
    LoginEventView,
    DriverDocumentView,
    DriverDocumentUploadView,
    DriverListView,
    DriverDetailView,
)

urlpatterns = [
    # Called by Flutter after Firebase signup
    path('register/', DriverRegisterView.as_view(), name='driver-register'),

    # Called by Flutter after Firebase login
    path('login-event/', LoginEventView.as_view(), name='driver-login-event'),

    # Called by Flutter to record document metadata (Firebase Storage URL)
    path('documents/', DriverDocumentView.as_view(), name='driver-documents'),

    # Called by Flutter to upload actual file bytes to Django
    path('documents/upload/', DriverDocumentUploadView.as_view(), name='driver-doc-upload'),

    # Admin dashboard — list all drivers
    path('', DriverListView.as_view(), name='driver-list'),

    # Admin dashboard — single driver by firebase_uid
    path('<str:firebase_uid>/', DriverDetailView.as_view(), name='driver-detail'),
]

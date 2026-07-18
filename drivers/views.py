import os
from rest_framework import generics, status
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from django.conf import settings

from .models import DriverProfile, DriverDocument, LoginEvent
from .serializers import (
    DriverProfileSerializer,
    DriverDocumentSerializer,
    LoginEventSerializer,
)


class DriverRegisterView(generics.CreateAPIView):
    """
    POST /api/drivers/register/
    Creates or updates a DriverProfile in PostgreSQL.
    Called by the Flutter app immediately after Firebase Auth signup.
    """
    serializer_class = DriverProfileSerializer
    permission_classes = [AllowAny]

    def create(self, request, *args, **kwargs):
        uid = request.data.get('firebase_uid')
        if not uid:
            return Response({'error': 'firebase_uid is required'}, status=status.HTTP_400_BAD_REQUEST)

        # Upsert: update if driver already exists, else create
        existing = DriverProfile.objects.filter(firebase_uid=uid).first()
        if existing:
            serializer = self.get_serializer(existing, data=request.data, partial=True)
        else:
            serializer = self.get_serializer(data=request.data)

        serializer.is_valid(raise_exception=True)
        serializer.save()
        http_status = status.HTTP_200_OK if existing else status.HTTP_201_CREATED
        return Response(serializer.data, status=http_status)


class LoginEventView(generics.CreateAPIView):
    """
    POST /api/drivers/login-event/
    Records a login timestamp for a driver.
    Called by the Flutter app after every successful Firebase Auth sign-in.
    """
    serializer_class = LoginEventSerializer
    permission_classes = [AllowAny]


class DriverDocumentView(generics.CreateAPIView):
    """
    POST /api/drivers/documents/
    Records document metadata (Firebase Storage URL, doc type) in PostgreSQL.
    """
    serializer_class = DriverDocumentSerializer
    permission_classes = [AllowAny]


class DriverDocumentUploadView(APIView):
    """
    POST /api/drivers/documents/upload/
    Accepts an actual file upload (multipart/form-data), saves it to
    MEDIA_ROOT/driver_docs/, and records the path in PostgreSQL.
    """
    parser_classes = [MultiPartParser, FormParser]
    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        uid = request.data.get('firebase_uid')
        doc_type = request.data.get('doc_type', 'driving_license')
        uploaded_file = request.FILES.get('file')

        if not uid or not uploaded_file:
            return Response(
                {'error': 'firebase_uid and file are required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Save file to MEDIA_ROOT/driver_docs/<uid>/
        save_dir = os.path.join(settings.MEDIA_ROOT, 'driver_docs', uid)
        os.makedirs(save_dir, exist_ok=True)
        file_path = os.path.join(save_dir, uploaded_file.name)
        with open(file_path, 'wb+') as dest:
            for chunk in uploaded_file.chunks():
                dest.write(chunk)

        # Construct a URL (served by Django if MEDIA_URL is configured)
        relative = f'driver_docs/{uid}/{uploaded_file.name}'
        file_url = request.build_absolute_uri(f'{settings.MEDIA_URL}{relative}')

        # Persist metadata
        driver, _ = DriverProfile.objects.get_or_create(
            firebase_uid=uid,
            defaults={'name': '', 'email': ''},
        )
        doc = DriverDocument.objects.create(
            driver=driver,
            doc_type=doc_type,
            file_url=file_url,
            file_name=uploaded_file.name,
        )

        return Response(
            {'id': doc.id, 'file_url': file_url, 'doc_type': doc_type},
            status=status.HTTP_201_CREATED,
        )


class DriverListView(generics.ListAPIView):
    """
    GET /api/drivers/
    Returns all registered drivers — used by the admin dashboard.
    """
    serializer_class = DriverProfileSerializer
    permission_classes = [AllowAny]  # Restrict this in production with IsAdminUser
    queryset = DriverProfile.objects.all()


class DriverDetailView(generics.RetrieveAPIView):
    """
    GET /api/drivers/<firebase_uid>/
    Returns a single driver's profile.
    """
    serializer_class = DriverProfileSerializer
    permission_classes = [AllowAny]
    queryset = DriverProfile.objects.all()
    lookup_field = 'firebase_uid'

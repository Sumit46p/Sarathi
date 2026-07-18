from rest_framework import serializers
from .models import DriverProfile, DriverDocument, LoginEvent


class DriverProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = DriverProfile
        fields = [
            'id', 'firebase_uid', 'name', 'email', 'phone',
            'vehicle_number', 'department', 'status', 'created_at',
        ]
        read_only_fields = ['id', 'status', 'created_at']


class DriverDocumentSerializer(serializers.ModelSerializer):
    # Accept firebase_uid directly instead of requiring a nested object
    firebase_uid = serializers.CharField(write_only=True)

    class Meta:
        model = DriverDocument
        fields = ['id', 'firebase_uid', 'doc_type', 'file_url', 'file_name', 'uploaded_at']
        read_only_fields = ['id', 'uploaded_at']

    def create(self, validated_data):
        uid = validated_data.pop('firebase_uid')
        driver, _ = DriverProfile.objects.get_or_create(
            firebase_uid=uid,
            defaults={'name': '', 'email': ''},
        )
        return DriverDocument.objects.create(driver=driver, **validated_data)


class LoginEventSerializer(serializers.ModelSerializer):
    firebase_uid = serializers.CharField()
    email = serializers.EmailField(required=False, allow_blank=True)

    class Meta:
        model = LoginEvent
        fields = ['id', 'firebase_uid', 'email', 'logged_in_at']
        read_only_fields = ['id', 'logged_in_at']

    def create(self, validated_data):
        uid = validated_data['firebase_uid']
        email = validated_data.get('email', '')
        # Try to link to an existing DriverProfile if one exists
        driver = DriverProfile.objects.filter(firebase_uid=uid).first()
        return LoginEvent.objects.create(
            driver=driver,
            firebase_uid=uid,
            email=email,
        )

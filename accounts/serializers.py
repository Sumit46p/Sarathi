from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from vehicles.models import Vehicle
from .models import Profile

class EmailOrUsernameTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Accept either a username or an email address as the login identifier."""

    username_field = User.USERNAME_FIELD

    def validate(self, attrs):
        identifier = attrs.get('username') or attrs.get('email')
        password = attrs.get('password')

        user = (
            User.objects.filter(username=identifier).first()
            or User.objects.filter(email__iexact=identifier).first()
        )

        if user is None or not user.check_password(password):
            raise serializers.ValidationError(
                'No active account found with the given credentials'
            )

        organization_name = self.initial_data.get('organization_name')
        if not hasattr(user, 'profile'):
            raise serializers.ValidationError(
                'User profile not found. Please contact support.'
            )
        
        # Case-insensitive organization name comparison
        if user.profile.organization_name.lower() != (organization_name or '').lower():
            raise serializers.ValidationError(
                f'Invalid organization name. Expected: {user.profile.organization_name}'
            )

        if not user.is_active:
            raise serializers.ValidationError(
                'No active account found with the given credentials'
            )

        attrs[self.username_field] = user.get_username()
        return super().validate(attrs)

class UserSerializer(serializers.ModelSerializer):
    organization_name = serializers.SerializerMethodField()

    def get_organization_name(self, obj):
        try:
            return obj.profile.organization_name
        except Exception:
            return None

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'organization_name')

class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(
        write_only=True,
        required=True,
        style={'input_type': 'password'}
    )
    email = serializers.EmailField(required=True)
    organization_name = serializers.CharField(
        write_only=True,
        required=True
    )

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'password', 'organization_name')

    def validate_password(self, value):
        try:
            validate_password(value)
        except DjangoValidationError as e:
            raise serializers.ValidationError(list(e.messages))
        return value

    def create(self, validated_data):
        org_name = validated_data.pop('organization_name')
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password']
        )
        # Use get_or_create to avoid duplicate profile errors
        # (the post_save signal may have already created one)
        profile, created = Profile.objects.get_or_create(
            user=user,
            defaults={'organization_name': org_name}
        )
        # Update org name if profile was created by signal with default
        if not created and profile.organization_name == 'Default Org':
            profile.organization_name = org_name
            profile.save()
        return user

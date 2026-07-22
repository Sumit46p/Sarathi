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

        if not user.is_active:
            raise serializers.ValidationError(
                'No active account found with the given credentials'
            )

        attrs[self.username_field] = user.get_username()
        return super().validate(attrs)

class UserSerializer(serializers.ModelSerializer):
    organization_type = serializers.SerializerMethodField()

    def get_organization_type(self, obj):
        try:
            return obj.profile.organization_type
        except Exception:
            return None

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'organization_type')

class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(
        write_only=True,
        required=True,
        style={'input_type': 'password'}
    )
    email = serializers.EmailField(required=True)
    organization_type = serializers.ChoiceField(
        choices=Vehicle.VEHICLE_TYPE_CHOICES,
        write_only=True,
        required=True
    )

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'password', 'organization_type')

    def validate_password(self, value):
        try:
            validate_password(value)
        except DjangoValidationError as e:
            raise serializers.ValidationError(list(e.messages))
        return value

    def create(self, validated_data):
        org_type = validated_data.pop('organization_type')
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password']
        )
        Profile.objects.create(user=user, organization_type=org_type)
        return user
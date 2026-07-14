from rest_framework import serializers
from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from vehicles.models import Vehicle
from .models import Profile

class UserSerializer(serializers.ModelSerializer):
    organization_type = serializers.CharField(source='profile.organization_type', read_only=True)

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
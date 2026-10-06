"""
Test Suite for Accounts App - Authentication, Authorization, and User Management
"""
from django.test import TestCase
from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.test import APITestCase, APIClient
from rest_framework import status
from datetime import timedelta

from accounts.models import Organization, Profile, get_organization_name


class OrganizationModelTestCase(TestCase):
    """Test Organization model functionality."""

    def test_organization_creation(self):
        org = Organization.objects.create(
            name="Test Fleet Company",
            organization_type="LOGISTICS",
            contact_information="contact@testfleet.com",
            address="123 Fleet Street, Kathmandu",
            status="active",
        )
        self.assertEqual(org.name, "Test Fleet Company")
        self.assertEqual(org.organization_type, "LOGISTICS")
        self.assertEqual(str(org), "Test Fleet Company")

    def test_organization_default_status(self):
        org = Organization.objects.create(name="Default Status Org")
        self.assertEqual(org.status, "active")


class ProfileModelTestCase(TestCase):
    """Test user Profile model and role-based access."""

    def setUp(self):
        self.org = Organization.objects.create(
            name="Profile Test Org", organization_type="GOVERNMENT"
        )
        # post_save signal auto-creates a Profile; we work with it below
        self.user = User.objects.create_user(
            username="testuser", password="testpass123", email="test@example.com"
        )

    def test_profile_creation(self):
        # Signal auto-creates the profile; update it with test-specific values
        profile, _ = Profile.objects.update_or_create(
            user=self.user,
            defaults={
                "organization": self.org,
                "organization_name": "Profile Test Org",
                "role": "FLEET_MANAGER",
            },
        )
        self.assertEqual(profile.user, self.user)
        self.assertEqual(profile.organization, self.org)
        self.assertEqual(profile.role, "FLEET_MANAGER")

    def test_profile_default_role(self):
        # The signal creates the profile with default role='VIEWER'
        profile = self.user.profile
        profile.organization = self.org
        profile.save()
        self.assertEqual(profile.role, "VIEWER")

    def test_profile_is_online_no_activity(self):
        profile = self.user.profile
        profile.organization = self.org
        profile.last_app_activity = None
        profile.save()
        self.assertIsNone(profile.last_app_activity)
        self.assertFalse(profile.is_online)

    def test_profile_is_online_recent_activity(self):
        profile = self.user.profile
        profile.organization = self.org
        profile.last_app_activity = timezone.now()
        profile.save()
        self.assertTrue(profile.is_online)

    def test_profile_online_threshold_boundary(self):
        profile = self.user.profile
        profile.organization = self.org
        profile.last_app_activity = timezone.now() - timedelta(minutes=4)
        profile.save()
        self.assertTrue(profile.is_online)
        profile.last_app_activity = timezone.now() - timedelta(minutes=6)
        profile.save()
        self.assertFalse(profile.is_online)


class GetOrganizationNameTestCase(TestCase):
    """Test global organization name resolution logic."""

    def test_get_organization_name_no_profiles(self):
        name = get_organization_name()
        self.assertEqual(name, "Default Org")

    def test_get_organization_name_with_admin_profile(self):
        org = Organization.objects.create(name="Admin Org")
        admin_user = User.objects.create_user(username="admin1", password="admin123")
        # Update the signal-created profile instead of creating a duplicate
        Profile.objects.filter(user=admin_user).update(
            organization=org,
            organization_name="Custom Admin Org",
            role="SUPER_ADMIN",
        )
        name = get_organization_name()
        self.assertEqual(name, "Custom Admin Org")


class AuthenticationTestCase(APITestCase):
    """Test authentication and authorization."""

    def setUp(self):
        self.org = Organization.objects.create(name="Auth Test Org")
        self.user = User.objects.create_user(
            username="authuser", password="authpass123", email="auth@test.com"
        )
        # Update the signal-created profile instead of creating a duplicate
        Profile.objects.filter(user=self.user).update(
            organization=self.org,
            organization_name="Auth Test Org",
            role="ORGANIZATION_ADMIN",
        )
        self.profile = self.user.profile
        self.client = APIClient()

    def test_authentication_required(self):
        response = self.client.get("/api/vehicles/")
        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_user_profile_relationship(self):
        self.assertEqual(self.user.profile, self.profile)
        self.assertEqual(self.profile.user, self.user)


class RoleBasedAccessTestCase(TestCase):
    """Test role-based permissions and access control."""

    def setUp(self):
        self.org = Organization.objects.create(name="RBAC Test Org")
        self.super_admin = User.objects.create_user(
            username="superadmin", password="super123"
        )
        # Update the auto-created profile instead of creating a duplicate.
        # Use the profile instance directly and save it so the in-memory
        # object is kept in sync (bulk .update() bypasses the instance cache).
        super_admin_profile = self.super_admin.profile
        super_admin_profile.organization = self.org
        super_admin_profile.role = "SUPER_ADMIN"
        super_admin_profile.save()
        # Clear Django's cached accessor so tests re-read from the instance
        if hasattr(self.super_admin, '_profile_cache'):
            del self.super_admin._profile_cache

        self.driver = User.objects.create_user(username="driver", password="driver123")
        driver_profile = self.driver.profile
        driver_profile.organization = self.org
        driver_profile.role = "DRIVER"
        driver_profile.save()
        if hasattr(self.driver, '_profile_cache'):
            del self.driver._profile_cache

    def test_role_assignment(self):
        self.assertEqual(self.super_admin.profile.role, "SUPER_ADMIN")
        self.assertEqual(self.driver.profile.role, "DRIVER")

    def test_organization_membership(self):
        self.assertEqual(self.super_admin.profile.organization, self.org)
        self.assertEqual(self.driver.profile.organization, self.org)

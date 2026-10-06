"""
Comprehensive Test Suite for Sarathi Fleet Management System
Tests: Models, Dispatch Engine, API Endpoints, GPS Processing
"""
from django.test import TestCase, TransactionTestCase
from django.contrib.auth.models import User
from django.contrib.gis.geos import Point
from django.utils import timezone
from rest_framework.test import APITestCase, APIClient
from rest_framework import status
from datetime import timedelta
import json

from vehicles.models import (
    Fleet, Driver, Vehicle, DispatchRequest, 
    MaintenanceRecord, FuelLog, LocationRecord
)
from vehicles.dispatch_engine import DispatchEngine, haversine, DispatchCandidate
from accounts.models import Organization, Profile


class HaversineDistanceTestCase(TestCase):
    """Test the haversine distance calculation function."""
    
    def test_haversine_same_point(self):
        """Distance between same point should be 0."""
        dist = haversine(27.7172, 85.3240, 27.7172, 85.3240)
        self.assertAlmostEqual(dist, 0.0, places=2)
    
    def test_haversine_kathmandu_pokhara(self):
        """Test known distance: Kathmandu to Pokhara ~145 km."""
        dist = haversine(27.7172, 85.3240, 28.2096, 83.9856)
        self.assertGreater(dist, 140)
        self.assertLess(dist, 150)
    
    def test_haversine_symmetry(self):
        """Distance A->B should equal B->A."""
        dist1 = haversine(27.7, 85.3, 28.2, 83.9)
        dist2 = haversine(28.2, 83.9, 27.7, 85.3)
        self.assertAlmostEqual(dist1, dist2, places=5)


class ModelTestCase(TestCase):
    """Test core model functionality and relationships."""
    
    def setUp(self):
        self.org = Organization.objects.create(name="Test Transport Co", organization_type="LOGISTICS", status="active")
        self.user = User.objects.create_user(username="testadmin", password="testpass123", email="admin@test.com")
        # Signal auto-creates profile; update it instead of creating a duplicate
        self.profile = self.user.profile
        self.profile.organization = self.org
        self.profile.organization_name = "Test Transport Co"
        self.profile.role = "ORGANIZATION_ADMIN"
        self.profile.save()
        self.fleet = Fleet.objects.create(name="Emergency Fleet", fleet_type="EMERGENCY", organization=self.org)
        self.driver = Driver.objects.create(name="Ram Bahadur", phone_number="+977-9841234567", license_number="DL-12345",
                                           is_active=True, is_on_duty=True, organization=self.org, fleet=self.fleet, owner=self.user)
    
    def test_organization_creation(self):
        self.assertEqual(self.org.name, "Test Transport Co")
        self.assertEqual(self.org.status, "active")
    
    def test_driver_creation(self):
        self.assertEqual(self.driver.name, "Ram Bahadur")
        self.assertTrue(self.driver.is_on_duty)
        self.assertEqual(str(self.driver), "Ram Bahadur (DL-12345)")
    
    def test_vehicle_creation_and_availability(self):
        # We must provide last_location_at otherwise the vehicle is considered "stale"
        # and gps_is_healthy becomes False, making is_available False.
        vehicle = Vehicle.objects.create(name="Ambulance-01", vehicle_type="rental", fuel_type="diesel", number_plate="BA-1-AA-1234",
                                        is_available=True, driver=self.driver, location=Point(85.3240, 27.7172, srid=4326),
                                        last_location_at=timezone.now(), organization=self.org, fleet=self.fleet, owner=self.user)
        self.assertEqual(vehicle.name, "Ambulance-01")
        self.assertTrue(vehicle.is_available)
    
    def test_vehicle_stale_gps(self):
        vehicle = Vehicle.objects.create(name="Truck-01", vehicle_type="logistics", location=Point(85.3240, 27.7172, srid=4326),
                                        driver=self.driver, organization=self.org, owner=self.user)
        self.assertTrue(vehicle.is_stale)
        vehicle.last_location_at = timezone.now()
        vehicle.save()
        self.assertFalse(vehicle.is_stale)
        vehicle.last_location_at = timezone.now() - timedelta(minutes=10)
        vehicle.save()
        self.assertTrue(vehicle.is_stale)

class DispatchEngineTestCase(TestCase):
    """Test the intelligent dispatch engine logic."""
    
    def setUp(self):
        self.org = Organization.objects.create(name="Emergency Services", organization_type="EMERGENCY", status="active")
        self.user = User.objects.create_user(username="dispatcher", password="dispatch123", email="dispatch@test.com")
        # Signal auto-creates profile; update it instead of creating a duplicate
        self.profile = self.user.profile
        self.profile.organization = self.org
        self.profile.organization_name = "Emergency Services"
        self.profile.role = "FLEET_MANAGER"
        self.profile.last_app_activity = timezone.now()
        self.profile.save()
        self.fleet = Fleet.objects.create(name="Ambulance Fleet", fleet_type="EMERGENCY", organization=self.org)
        self.driver1 = Driver.objects.create(name="Driver One", phone_number="+977-9841111111", license_number="DL-00001",
                                            is_active=True, is_on_duty=True, organization=self.org, fleet=self.fleet, owner=self.user)
        self.vehicle1 = Vehicle.objects.create(name="Ambulance-01", vehicle_type="rental", fuel_type="diesel", number_plate="BA-1-AA-1111",
                                              is_available=True, driver=self.driver1, location=Point(85.3240, 27.7172, srid=4326),
                                              last_location_at=timezone.now(), organization=self.org, fleet=self.fleet, owner=self.user)
        self.driver1.user = self.user
        self.driver1.save()
    
    def test_dispatch_engine_emergency_prioritization(self):
        engine_emergency = DispatchEngine(target_lat=27.7172, target_lng=85.3240, vehicle_type="rental",
                                         request_type="EMERGENCY", priority="HIGH", organization=self.org)
        engine_normal = DispatchEngine(target_lat=27.7172, target_lng=85.3240, vehicle_type="rental",
                                      request_type="NORMAL", priority="MEDIUM", organization=self.org)
        self.assertGreater(engine_emergency.weight_eta, engine_normal.weight_eta)
        self.assertEqual(engine_emergency.weight_eta, 0.65)
        self.assertEqual(engine_normal.weight_eta, 0.45)





class MaintenanceTestCase(TestCase):
    """Test maintenance scheduling and tracking."""
    
    def setUp(self):
        self.org = Organization.objects.create(name="Fleet Ops", organization_type="LOGISTICS")
        self.user = User.objects.create_user(username="mechanic", password="mech123")
        self.vehicle = Vehicle.objects.create(name="Truck-01", vehicle_type="logistics", location=Point(85.3240, 27.7172, srid=4326),
                                             organization=self.org, owner=self.user)
    
    def test_maintenance_record_creation(self):
        maintenance = MaintenanceRecord.objects.create(vehicle=self.vehicle, maintenance_type="oil_change",
                                                      description="Regular oil change", due_date=timezone.now().date() + timedelta(days=7), cost=5000.00, owner=self.user)
        self.assertEqual(maintenance.vehicle, self.vehicle)
        self.assertEqual(maintenance.maintenance_type, "oil_change")
        self.assertFalse(maintenance.completed)
    
    def test_maintenance_completion(self):
        maintenance = MaintenanceRecord.objects.create(vehicle=self.vehicle, maintenance_type="inspection",
                                                      description="Annual inspection", due_date=timezone.now().date(), owner=self.user)
        maintenance.completed = True
        maintenance.completed_at = timezone.now()
        maintenance.save()
        self.assertTrue(maintenance.completed)
        self.assertIsNotNone(maintenance.completed_at)


class APIEndpointTestCase(APITestCase):
    """Test REST API endpoints."""
    
    def setUp(self):
        self.org = Organization.objects.create(name="API Test Org", organization_type="LOGISTICS")
        self.user = User.objects.create_user(username="apiuser", password="api123", email="api@test.com")
        # Signal auto-creates profile; update it instead of creating a duplicate
        self.profile = self.user.profile
        self.profile.organization = self.org
        self.profile.organization_name = "API Test Org"
        self.profile.role = "ORGANIZATION_ADMIN"
        self.profile.save()
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.vehicle = Vehicle.objects.create(name="Test Vehicle", vehicle_type="rental", location=Point(85.3240, 27.7172, srid=4326),
                                             organization=self.org, owner=self.user)
    
    def test_vehicle_list_api(self):
        response = self.client.get('/api/vehicles/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)


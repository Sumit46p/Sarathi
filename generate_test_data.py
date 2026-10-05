#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Test data generator for Sarathi Fleet Management System.
Run: python generate_test_data.py
"""
import os, sys, django, random
from datetime import datetime, timedelta
from decimal import Decimal

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'sarthi_backend.settings')
django.setup()

from django.contrib.auth.models import User
from django.contrib.gis.geos import Point
from vehicles.models import Vehicle, Driver, DispatchRequest, MaintenanceRecord, IssueReport, FuelLog, OperationalLocation
from accounts.models import Profile

LOCATIONS = [
    {'name': 'Kathmandu Durbar Square', 'lat': 27.7045, 'lng': 85.3077},
    {'name': 'Thamel', 'lat': 27.7145, 'lng': 85.3120},
    {'name': 'Tribhuvan Airport', 'lat': 27.6966, 'lng': 85.3591},
    {'name': 'Patan Durbar Square', 'lat': 27.6730, 'lng': 85.3250},
]

VEHICLE_NAMES = ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta']
DRIVER_NAMES = ['Ram Bahadur', 'Shyam Kumar', 'Hari Prasad', 'Gopal Singh', 'Krishna Thapa', 'Bishnu Rai']
PLATES = ['BA 1 PA 1234', 'BA 2 CHA 5678', 'BA 3 KA 9012', 'GA 1 KA 3456', 'LU 2 PA 7890', 'BA 5 JA 1357']

def rand_point(lat, lng, km=5):
    off = km/111
    return Point(lng + random.uniform(-off, off), lat + random.uniform(-off, off), srid=4326)

print("=" * 70)
print("GENERATING TEST DATA FOR SARATHI")
print("=" * 70)

# Admin
print("\nCreating admin user...")
if User.objects.filter(username='admin').exists():
    admin = User.objects.get(username='admin')
    print("   OK: Admin exists")
else:
    admin = User.objects.create_superuser('admin', 'admin@sarathi.com', 'admin123', first_name='Admin', last_name='User')
    Profile.objects.get_or_create(user=admin, defaults={'role': 'admin', 'organization_name': 'Sarathi Fleet'})
    print("   OK: Created admin / admin123")

# Clear existing test data
print("\nClearing existing test data...")
Vehicle.objects.filter(owner=admin).delete()
Driver.objects.filter(owner=admin).delete()
print("   OK: Cleared existing data")

# Vehicles
print("\nCreating 6 vehicles...")
vehicles = []
types = ['rental', 'logistics', 'company']
fuels = ['petrol', 'diesel', 'ev']
for i in range(6):
    loc = random.choice(LOCATIONS)
    v = Vehicle.objects.create(
        owner=admin, name=VEHICLE_NAMES[i], vehicle_type=random.choice(types),
        fuel_type=random.choice(fuels), number_plate=PLATES[i],
        location=rand_point(loc['lat'], loc['lng']), is_available=True
    )
    vehicles.append(v)
    print(f"   OK: {v.name} ({v.vehicle_type}) at {loc['name']}")

# Drivers
print("\nCreating 6 drivers...")
drivers = []
for i in range(6):
    username = f'driver{i+1}'
    if User.objects.filter(username=username).exists():
        user = User.objects.get(username=username)
    else:
        user = User.objects.create_user(username, f'{username}@sarathi.com', 'driver123')
    
    driver, _ = Driver.objects.get_or_create(
        user=user, defaults={'name': DRIVER_NAMES[i], 'phone_number': f'98{random.randint(10000000,99999999)}',
        'license_number': f'01-02-{random.randint(100000,999999)}', 'is_active': True, 'is_on_duty': True,
        'owner': admin}
    )
    
    if i < len(vehicles):
        vehicles[i].driver = driver
        vehicles[i].save()
        print(f"   OK: {driver.name} -> {vehicles[i].name}")
    drivers.append(driver)

# Operational Locations
print("\nCreating operational locations...")
for loc in LOCATIONS:
    OperationalLocation.objects.get_or_create(
        name=loc['name'], defaults={'address': f"{loc['name']}, Nepal",
        'location': Point(loc['lng'], loc['lat'], srid=4326), 'category': 'landmark'}
    )
print(f"   OK: {len(LOCATIONS)} locations")

# Fuel Logs
print("\nCreating 5 fuel logs...")
for i in range(5):
    v = random.choice(vehicles)
    liters = Decimal(random.uniform(20, 60))
    FuelLog.objects.create(vehicle=v, driver=v.driver, fuel_type=v.fuel_type, 
        liters=liters, amount=liters * Decimal('150'), 
        cost_per_liter=Decimal('150'), odometer_reading=Decimal(random.randint(5000, 20000)))
print("   OK: Created fuel logs")

# Maintenance
print("\nCreating 3 maintenance records...")
mtypes = ['oil_change', 'tire_rotation', 'inspection']
for i in range(3):
    v = random.choice(vehicles)
    MaintenanceRecord.objects.create(vehicle=v, owner=admin, maintenance_type=random.choice(mtypes),
        description=f'Maintenance for {v.name}', cost=Decimal(random.uniform(2000, 8000)),
        due_date=datetime.now().date() + timedelta(days=random.randint(-10, 30)), completed=False)
print("   OK: Created maintenance records")

print("\n" + "=" * 70)
print("TEST DATA GENERATION COMPLETE!")
print("=" * 70)
print(f"\nSummary:")
print(f"   Vehicles: {Vehicle.objects.count()}")
print(f"   Drivers: {Driver.objects.count()}")
print(f"   Fuel Logs: {FuelLog.objects.count()}")
print(f"   Maintenance: {MaintenanceRecord.objects.count()}")
print(f"\nLogin Credentials:")
print(f"   Admin: admin / admin123")
print(f"   Drivers: driver1-driver6 / driver123")
print(f"\nStart Servers:")
print(f"   Backend: python manage.py runserver")
print(f"   Frontend: cd frontend && npm run dev")
print(f"   Access: http://localhost:5173\n")

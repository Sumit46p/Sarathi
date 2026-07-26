from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance
from django.contrib.auth.models import User
from django.db.models import Q
from django.utils import timezone
from .osrm import get_route_distance
import threading
import math

from .models import Vehicle, DispatchRequest, Driver, MaintenanceRecord, MaintenanceTemplate, IssueReport
from .serializers import (
    VehicleSerializer,
    LocationUpdateSerializer,
    NearestVehicleSerializer,
    DispatchRequestInputSerializer,
    MaintenanceRecordSerializer,
    DispatchRequestSerializer,
    DriverSerializer,
    AssignDriverSerializer,
    DriverMeSerializer,
    IssueReportSerializer,
    MaintenanceTemplateSerializer,
)

def haversine_distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """
    Calculate great-circle distance between two points on Earth using Haversine formula.
    Returns distance in kilometers.
    
    Args:
        lat1, lng1: First point coordinates (degrees)
        lat2, lng2: Second point coordinates (degrees)
    
    Returns:
        Distance in kilometers
    """
    R = 6371.0  # Earth radius in km
    
    # Convert to radians
    lat1_rad = math.radians(lat1)
    lng1_rad = math.radians(lng1)
    lat2_rad = math.radians(lat2)
    lng2_rad = math.radians(lng2)
    
    # Haversine formula
    dlat = lat2_rad - lat1_rad
    dlng = lng2_rad - lng1_rad
    
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlng / 2) ** 2
    c = 2 * math.asin(math.sqrt(a))
    
    return R * c

def check_and_update_maintenance_due(vehicle: Vehicle) -> None:
    """
    Check if any maintenance records should be marked as due based on:
    - Calendar-based recurrence (recurrence_days)
    - Mileage-based recurrence (recurrence_km)
    
    This is called after every location update. For each maintenance type,
    we check if either recurrence threshold has been exceeded since the
    last completed record.
    """
    from datetime import timedelta
    
    # Group maintenance records by type, get the latest completed one for each
    completed_by_type = {}
    for record in vehicle.maintenance_records.filter(completed=True).order_by('-completed_at'):
        if record.maintenance_type not in completed_by_type:
            completed_by_type[record.maintenance_type] = record
    
    # Check each active (not completed) maintenance record
    for record in vehicle.maintenance_records.filter(completed=False):
        is_due = False
        reason = None
        
        # Check calendar-based recurrence
        if record.recurrence_days:
            if record.recurrence_days and record.due_date <= timezone.now().date():
                is_due = True
                reason = 'calendar-based'
        
        # Check mileage-based recurrence
        if not is_due and record.recurrence_km:
            last_completed = completed_by_type.get(record.maintenance_type)
            if last_completed:
                # Calculate km driven since last completion
                km_since_completion = vehicle.total_distance_km - (last_completed.vehicle.total_distance_km if hasattr(last_completed, 'vehicle') else 0)
                # This is approximate; ideally we'd track km at completion time
                # For now, we can store that in a future enhancement
                if km_since_completion >= record.recurrence_km:
                    is_due = True
                    reason = 'mileage-based'
        
        # Mark as due if threshold exceeded (update due_date to today if needed)
        if is_due and record.due_date > timezone.now().date():
            record.due_date = timezone.now().date()
            record.save(update_fields=['due_date'])


class VehicleListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/vehicles/      — list all vehicles with current location
    POST /api/vehicles/      — create a new vehicle (for testing without admin)
    """
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Vehicle.objects.filter(owner=self.request.user)

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)


class VehicleDetailView(generics.RetrieveUpdateDestroyAPIView):
    """
    GET    /api/vehicles/<id>/  — detail of one vehicle
    PATCH  /api/vehicles/<id>/  — partial update (toggle is_available, edit details)
    DELETE /api/vehicles/<id>/  — remove a vehicle
    """
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return Vehicle.objects.filter(
            Q(owner=user) | Q(driver__user=user)
        )

    def update(self, request, *args, **kwargs):
        instance = self.get_object()
        is_owner = instance.owner == request.user
        is_assigned_driver = (
            instance.driver is not None
            and instance.driver.user is not None
            and instance.driver.user == request.user
        )

        if not (is_owner or is_assigned_driver):
            return Response(
                {'error': 'Vehicle not found or access denied'},
                status=status.HTTP_404_NOT_FOUND,
            )

        if is_assigned_driver and not is_owner:
            allowed_fields = {'is_available'}
            requested_fields = set(request.data.keys())
            if not requested_fields.issubset(allowed_fields):
                return Response(
                    {'error': 'Assigned drivers may only update is_available'},
                    status=status.HTTP_403_FORBIDDEN,
                )

        return super().update(request, *args, **kwargs)


class DriverListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/drivers/      — list all drivers
    POST /api/drivers/      — create a new driver
    """
    serializer_class = DriverSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Driver.objects.filter(owner=self.request.user)

    def get_serializer_context(self):
        context = super().get_serializer_context()
        # Pass organization_name from user's profile to serializer
        org_name = 'Default Org'
        try:
            if hasattr(self.request.user, 'profile'):
                org_name = self.request.user.profile.organization_name
        except Exception:
            pass
        context['organization_name'] = org_name
        return context

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)


class DriverDetailView(generics.RetrieveUpdateDestroyAPIView):
    """
    GET    /api/drivers/<id>/  — detail of one driver
    PATCH  /api/drivers/<id>/  — partial update
    DELETE /api/drivers/<id>/  — remove a driver AND its linked User account
    """
    serializer_class = DriverSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Driver.objects.filter(owner=self.request.user)

    def perform_destroy(self, instance):
        """Delete the linked Django User when the driver is removed so the
        username can be reused immediately."""
        linked_user = instance.user
        instance.delete()
        if linked_user is not None:
            linked_user.delete()


def safe_route_geometry(vehicle, dispatch, deadline=3.0):
    """Best-effort live route geometry from vehicle to dispatch request.

    Runs OSRM in a separate thread with a hard deadline so an unreachable
    router can never block the API response. Returns None on any failure or
    timeout (the client falls back to a straight line).
    """
    if vehicle.location is None:
        return None

    result = {}

    def _compute():
        try:
            _, _, geom = get_route_distance(
                vehicle.location.y, vehicle.location.x,
                dispatch.request_lat, dispatch.request_lng,
            )
            result['geometry'] = geom
        except Exception:
            result['geometry'] = None

    worker = threading.Thread(target=_compute, daemon=True)
    worker.start()
    worker.join(timeout=deadline)
    if worker.is_alive():
        return None
    return result['geometry']


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def active_dispatch(request):
    """Return the owner's latest active dispatch with live route geometry."""
    dispatch = (
        DispatchRequest.objects
        .select_related('assigned_vehicle')
        .filter(
            assigned_vehicle__owner=request.user,
            status__in=ACTIVE_DISPATCH_STATUSES,
        )
        .order_by('-created_at')
        .first()
    )
    if dispatch is None:
        return Response(
            {'error': 'No active dispatch for any of your vehicles'},
            status=status.HTTP_404_NOT_FOUND,
        )

    data = DispatchRequestSerializer(dispatch).data
    data['geometry'] = safe_route_geometry(dispatch.assigned_vehicle, dispatch)
    return Response(data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_me(request):
    """
    GET /api/drivers/me/
    Returns the Driver record linked to the current authenticated user,
    plus their currently assigned vehicle (if any).
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    assigned_vehicle = None
    if driver.assigned_vehicles.exists():
        v = driver.assigned_vehicles.first()
        assigned_vehicle = {
            'id': v.id,
            'name': v.name,
            'vehicle_type': v.vehicle_type,
            'number_plate': v.number_plate,
            'is_available': v.is_available,
            'location': {'lat': v.location.y, 'lng': v.location.x} if v.location else None,
        }

    data = {
        'id': driver.id,
        'name': driver.name,
        'phone_number': driver.phone_number,
        'license_number': driver.license_number,
        'is_active': driver.is_active,
        'requires_password_change': driver.requires_password_change,
        'is_on_duty': driver.is_on_duty,
        'assigned_vehicle': assigned_vehicle,
    }
    serializer = DriverMeSerializer(data)
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_change_password(request):
    """
    POST /api/drivers/me/change-password/
    Body: {"new_password": "..."}
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response({'error': 'Driver profile not found'}, status=status.HTTP_404_NOT_FOUND)

    new_password = request.data.get('new_password')
    if not new_password or len(new_password) < 6:
        return Response({'error': 'Password must be at least 6 characters'}, status=status.HTTP_400_BAD_REQUEST)

    user = request.user
    user.set_password(new_password)
    user.save()

    driver.requires_password_change = False
    driver.save(update_fields=['requires_password_change'])

    return Response({'success': True})


@api_view(['POST'])
def reset_password(request):
    """
    POST /api/drivers/reset-password/
    Body: {"username": "...", "organization_name": "...", "new_password": "..."}
    Allows resetting password after verifying username and organization name.
    """
    username = request.data.get('username')
    organization_name = request.data.get('organization_name')
    new_password = request.data.get('new_password')

    if not all([username, organization_name, new_password]):
        return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)
    
    if len(new_password) < 6:
        return Response({'error': 'Password must be at least 6 characters'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username)
        if not hasattr(user, 'profile'):
            return Response({'error': 'User profile not found'}, status=status.HTTP_400_BAD_REQUEST)
        # Validate against the canonical (admin's) org name, not the user's own
        from accounts.models import get_organization_name
        expected_org = get_organization_name()
        if expected_org.lower() != (organization_name or '').lower():
            return Response({'error': f'Invalid organization name. Expected: {expected_org}'}, status=status.HTTP_400_BAD_REQUEST)
        driver = Driver.objects.get(user=user)
    except (User.DoesNotExist, Driver.DoesNotExist):
        return Response({'error': 'Invalid username or organization name'}, status=status.HTTP_400_BAD_REQUEST)

    user.set_password(new_password)
    user.save()

    driver.requires_password_change = False
    driver.save(update_fields=['requires_password_change'])

    return Response({'success': True})


@api_view(['POST'])
def verify_driver_identity(request):
    """
    POST /api/drivers/verify-identity/
    Body: {"username": "...", "organization_name": "..."}
    Verifies if a driver exists for the given username and organization name.
    """
    username = request.data.get('username')
    organization_name = request.data.get('organization_name')

    if not all([username, organization_name]):
        return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username)
        if not hasattr(user, 'profile'):
            return Response({'error': 'User profile not found'}, status=status.HTTP_400_BAD_REQUEST)
        # Validate against the canonical (admin's) org name, not the user's own
        from accounts.models import get_organization_name
        expected_org = get_organization_name()
        if expected_org.lower() != (organization_name or '').lower():
            return Response({'error': f'Invalid organization name. Expected: {expected_org}'}, status=status.HTTP_400_BAD_REQUEST)
        driver = Driver.objects.get(user=user)
    except (User.DoesNotExist, Driver.DoesNotExist):
        return Response({'error': 'No driver account found'}, status=status.HTTP_400_BAD_REQUEST)

    return Response({'success': True, 'message': 'Identity verified'})


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def driver_duty(request):
    """
    PATCH /api/drivers/me/duty/
    Body: {"is_on_duty": true|false}
    Sets the driver's duty status. Availability of the assigned vehicle is
    derived (driver on duty AND not admin-blocked) via the Vehicle signal.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    on_duty = request.data.get('is_on_duty')
    if not isinstance(on_duty, bool):
        return Response(
            {'error': 'is_on_duty must be a boolean'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    driver.is_on_duty = on_duty
    driver.save(update_fields=['is_on_duty'])
    # Force refresh driver from DB in case signal processing affects related objects
    driver.refresh_from_db()

    assigned_vehicle = None
    if driver.assigned_vehicles.exists():
        v = driver.assigned_vehicles.first()
        # Refresh from DB to get the updated is_available after signal fired
        v.refresh_from_db()
        assigned_vehicle = {
            'id': v.id,
            'name': v.name,
            'vehicle_type': v.vehicle_type,
            'number_plate': v.number_plate,
            'is_available': v.is_available,
            'location': {'lat': v.location.y, 'lng': v.location.x} if v.location else None,
        }

    data = {
        'id': driver.id,
        'name': driver.name,
        'phone_number': driver.phone_number,
        'license_number': driver.license_number,
        'is_active': driver.is_active,
        'requires_password_change': driver.requires_password_change,
        'is_on_duty': driver.is_on_duty,
        'assigned_vehicle': assigned_vehicle,
    }
    return Response(DriverMeSerializer(data).data)


ACTIVE_DISPATCH_STATUSES = ['assigned', 'accepted', 'en_route', 'arrived']


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_dispatch(request):
    """
    GET /api/drivers/me/dispatch/
    Returns the active DispatchRequest (if any) for the driver's assigned
    vehicle, including route geometry for the map.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicle = driver.assigned_vehicles.first()
    if vehicle is None:
        return Response(
            {'error': 'No vehicle is assigned to this driver'},
            status=status.HTTP_404_NOT_FOUND,
        )

    dispatch = (
        DispatchRequest.objects
        .filter(assigned_vehicle=vehicle, status__in=ACTIVE_DISPATCH_STATUSES)
        .first()
    )
    if dispatch is None:
        return Response(
            {'error': 'No active dispatch for this driver'},
            status=status.HTTP_404_NOT_FOUND,
        )

    data = DispatchRequestSerializer(dispatch).data
    data['geometry'] = safe_route_geometry(vehicle, dispatch)
    return Response(data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_dispatch_transition(request):
    """
    POST /api/drivers/me/dispatch/transition/
    Body: {"status": "accepted"|"en_route"|"arrived"|"completed"}
    Advances the active dispatch through its state machine.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicle = driver.assigned_vehicles.first()
    if vehicle is None:
        return Response(
            {'error': 'No vehicle is assigned to this driver'},
            status=status.HTTP_404_NOT_FOUND,
        )

    dispatch = (
        DispatchRequest.objects
        .filter(assigned_vehicle=vehicle, status__in=ACTIVE_DISPATCH_STATUSES)
        .first()
    )
    if dispatch is None:
        return Response(
            {'error': 'No active dispatch for this driver'},
            status=status.HTTP_404_NOT_FOUND,
        )

    new_status = request.data.get('status')
    if new_status not in DispatchRequest.VALID_TRANSITIONS.get(dispatch.status, []):
        return Response(
            {'error': f"Invalid transition from '{dispatch.status}' to '{new_status}'"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        dispatch.transition_to(new_status)
    except ValueError as e:
        return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)

    data = DispatchRequestSerializer(dispatch).data
    data['geometry'] = safe_route_geometry(vehicle, dispatch)
    return Response(data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def dispatch_transition(request, pk):
    """
    POST /api/vehicles/<pk>/dispatch/transition/
    Body: {"status": "accepted"|"en_route"|"arrived"|"completed"|"cancelled"}
    Owner-scoped (admin) advance of the active dispatch for this vehicle.
    Lets the dispatcher accept/reject from the dashboard; first acceptor wins.
    """
    try:
        vehicle = Vehicle.objects.get(pk=pk, owner=request.user)
    except Vehicle.DoesNotExist:
        return Response(
            {'error': 'Vehicle not found or access denied'},
            status=status.HTTP_404_NOT_FOUND,
        )

    dispatch = (
        DispatchRequest.objects
        .filter(assigned_vehicle=vehicle, status__in=ACTIVE_DISPATCH_STATUSES)
        .first()
    )
    if dispatch is None:
        return Response(
            {'error': 'No active dispatch for this vehicle'},
            status=status.HTTP_404_NOT_FOUND,
        )

    new_status = request.data.get('status')
    if new_status not in DispatchRequest.VALID_TRANSITIONS.get(dispatch.status, []):
        return Response(
            {'error': f"Invalid transition from '{dispatch.status}' to '{new_status}'"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        dispatch.transition_to(new_status)
    except ValueError as e:
        return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)

    data = DispatchRequestSerializer(dispatch).data
    data['geometry'] = safe_route_geometry(vehicle, dispatch)
    return Response(data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def update_location(request, pk):
    """
    POST /api/vehicles/<id>/update-location/
    Body: {"lat": 26.54, "lng": 87.89}

    Updates the vehicle's GPS location and returns the updated vehicle.
    Calculates GPS-based distance using haversine formula with noise filtering:
    - Only adds distance if > 15m (filters GPS jitter from stationary vehicles)
    - Accumulates into total_distance_km for mileage-based maintenance triggers
    
    Allowed for the vehicle owner or the assigned driver.
    """
    try:
        vehicle = Vehicle.objects.get(pk=pk)
    except Vehicle.DoesNotExist:
        return Response(
            {'error': f'Vehicle {pk} not found'},
            status=status.HTTP_404_NOT_FOUND,
        )

    is_owner = vehicle.owner == request.user
    is_assigned_driver = (
        vehicle.driver is not None
        and vehicle.driver.user is not None
        and vehicle.driver.user == request.user
    )

    if not (is_owner or is_assigned_driver):
        return Response(
            {'error': 'Vehicle not found or access denied'},
            status=status.HTTP_404_NOT_FOUND,
        )

    serializer = LocationUpdateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    new_lat = serializer.validated_data['lat']
    new_lng = serializer.validated_data['lng']
    new_location = Point(new_lng, new_lat, srid=4326)

    # Calculate distance from previous location if it exists
    NOISE_THRESHOLD_METERS = 15
    distance_increment_km = 0
    
    if vehicle.location is not None:
        # Calculate great-circle distance using haversine formula
        distance_m = haversine_distance_km(
            vehicle.location.y,  # previous lat
            vehicle.location.x,  # previous lng
            new_lat,
            new_lng,
        ) * 1000  # Convert to meters
        
        # Only count distance if above noise threshold (likely real movement, not GPS jitter)
        if distance_m > NOISE_THRESHOLD_METERS:
            distance_increment_km = distance_m / 1000
            vehicle.total_distance_km += distance_increment_km
    
    vehicle.location = new_location
    vehicle.last_location_at = timezone.now()
    vehicle.save(update_fields=['location', 'last_location_at', 'total_distance_km'])

    # Check if any maintenance records should be marked as due
    # (calendar or mileage-based recurrence)
    check_and_update_maintenance_due(vehicle)

    return Response(VehicleSerializer(vehicle).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def assign_driver(request, pk):
    """
    POST /api/vehicles/<id>/assign-driver/
    Body: {"driver_id": 5} or {"driver_id": null}
    """
    try:
        vehicle = Vehicle.objects.get(pk=pk, owner=request.user)
    except Vehicle.DoesNotExist:
        return Response(
            {'error': 'Vehicle not found or access denied'},
            status=status.HTTP_404_NOT_FOUND,
        )

    serializer = AssignDriverSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    driver_id = serializer.validated_data.get('driver_id')
    if driver_id is None:
        vehicle.driver = None
    else:
        try:
            driver = Driver.objects.get(pk=driver_id, owner=request.user)
            vehicle.driver = driver
        except Driver.DoesNotExist:
            return Response(
                {'error': 'Driver not found or access denied'},
                status=status.HTTP_404_NOT_FOUND,
            )

    vehicle.save(update_fields=['driver'])
    return Response(VehicleSerializer(vehicle).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def nearest_vehicles(request):
    """
    GET /api/vehicles/nearest/?lat=..&lng=..&type=..
    Returns the top 5 available vehicles of the given type ordered by
    straight-line PostGIS distance. Scoped to request.user.
    """
    try:
        lat = float(request.query_params['lat'])
        lng = float(request.query_params['lng'])
        vehicle_type = request.query_params['type']
    except (KeyError, ValueError):
        return Response(
            {'error': 'Required query params: lat, lng, type'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    request_point = Point(lng, lat, srid=4326)

    vehicles = (
        Vehicle.objects
        .filter(owner=request.user, is_available=True, vehicle_type=vehicle_type)
        .annotate(distance=Distance('location', request_point))
        .order_by('distance')[:5]
    )

    results = []
    for v in vehicles:
        results.append({
            'id': v.id,
            'name': v.name,
            'distance_km': round(v.distance.km, 2),
            'lat': v.location.y,
            'lng': v.location.x,
        })

    serializer = NearestVehicleSerializer(results, many=True)
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def dispatch_vehicle(request):
    """
    POST /api/dispatch/
    Body: {"lat": ..., "lng": ..., "vehicle_type": "ambulance"}

    Two-stage dispatch:
      1. PostGIS straight-line distance narrows candidates to top 5
      2. OSRM real-road distance ranks those 5 to pick the true nearest
    Falls back to straight-line ranking if OSRM is unreachable.
    """
    serializer = DispatchRequestInputSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    lat = serializer.validated_data['lat']
    lng = serializer.validated_data['lng']
    vehicle_type = serializer.validated_data['vehicle_type']

    request_point = Point(lng, lat, srid=4326)

    # Stage 1: PostGIS straight-line pre-filter (fast, approximate)
    candidates = list(
        Vehicle.objects
        .filter(owner=request.user, is_available=True, vehicle_type=vehicle_type)
        .annotate(distance=Distance('location', request_point))
        .order_by('distance')[:5]
    )

    if not candidates:
        return Response(
            {'error': f'No available {vehicle_type} vehicles found in your organization'},
            status=status.HTTP_404_NOT_FOUND,
        )

    # Stage 2: OSRM real-road ranking on the shortlist
    ranked = []
    osrm_succeeded = False
    for v in candidates:
        distance_km, duration_min, geometry = get_route_distance(
            v.location.y, v.location.x, lat, lng
        )
        if distance_km is not None:
            osrm_succeeded = True
            ranked.append({
                'vehicle': v,
                'distance_km': distance_km,
                'duration_min': duration_min,
                'geometry': geometry
            })
        else:
            # Fallback for this candidate: straight-line distance, no ETA, no geometry
            ranked.append({
                'vehicle': v,
                'distance_km': round(v.distance.km, 2),
                'duration_min': None,
                'geometry': None
            })

    ranked.sort(key=lambda x: x['distance_km'])
    best = ranked[0]
    nearest = best['vehicle']

    # Mark vehicle as unavailable
    nearest.is_available = False
    nearest.save(update_fields=['is_available'])

    # Create dispatch record with the computed distance/duration saved once
    now = timezone.now()
    dispatch = DispatchRequest.objects.create(
        request_lat=lat,
        request_lng=lng,
        vehicle_type=vehicle_type,
        assigned_vehicle=nearest,
        status='assigned',
        assigned_at=now,
        distance_km=best['distance_km'],
        duration_min=best['duration_min'],
        used_osrm=osrm_succeeded,
    )

    return Response({
        'dispatch': DispatchRequestSerializer(dispatch).data,
        'assigned_vehicle': {
            'id': nearest.id,
            'name': nearest.name,
            'lat': nearest.location.y,
            'lng': nearest.location.x,
        },
        'distance_km': best['distance_km'],
        'duration_min': best['duration_min'],
        'geometry': best['geometry'],
    },
    status=status.HTTP_201_CREATED)

class MaintenanceRecordListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/maintenance/      — list all maintenance records
    POST /api/maintenance/      — create a new maintenance record
    """
    serializer_class = MaintenanceRecordSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return MaintenanceRecord.objects.filter(owner=self.request.user)

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)

class MaintenanceRecordDetailView(generics.RetrieveUpdateDestroyAPIView):
    """
    GET    /api/maintenance/<id>/  — detail of one maintenance record
    PATCH  /api/maintenance/<id>/  — partial update
    DELETE /api/maintenance/<id>/  — remove a maintenance record
    """
    serializer_class = MaintenanceRecordSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return MaintenanceRecord.objects.filter(owner=self.request.user)

    def perform_update(self, serializer):
        # Auto-set completed_at when completed is marked True
        completed = serializer.validated_data.get('completed', None)
        if completed:
            serializer.save(completed_at=timezone.now())
        else:
            serializer.save()


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def upcoming_maintenance(request):
    """
    GET /api/maintenance/upcoming/
    Returns maintenance records where due_date is in the next 30 days
    """
    today = timezone.now().date()
    thirty_days_later = today + timezone.timedelta(days=30)

    records = MaintenanceRecord.objects.filter(
        owner=request.user,
        due_date__range=[today, thirty_days_later]
    ).order_by('due_date')

    serializer = MaintenanceRecordSerializer(records, many=True)
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def report_issue(request):
    """
    POST /api/drivers/me/report-issue/
    Body (multipart/form-data):
      - description (text, required)
      - image (file, optional)
    Creates an issue report for the driver linked to the current user.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    description = request.data.get('description', '').strip()
    if not description:
        return Response(
            {'error': 'Description is required'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    image = request.data.get('image') if 'image' in request.data else None

    report = IssueReport.objects.create(
        driver=driver,
        description=description,
        image=image,
    )

    serializer = IssueReportSerializer(report)
    return Response(serializer.data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def issue_report_list(request):
    """
    GET /api/issues/
    Returns all issue reports for the current owner (org-scoped),
    sorted newest first.
    """
    reports = IssueReport.objects.filter(driver__owner=request.user).select_related('driver')
    serializer = IssueReportSerializer(reports, many=True)
    return Response(serializer.data)


@api_view(['GET', 'PATCH'])
@permission_classes([IsAuthenticated])
def issue_report_detail(request, pk):
    """
    GET    /api/issues/<id>/
    PATCH  /api/issues/<id>/
    Returns/updates a single issue report owned by the current owner.
    PATCH accepts {"status": "open"|"acknowledged"|"resolved"}.
    """
    try:
        report = IssueReport.objects.get(pk=pk, driver__owner=request.user)
    except IssueReport.DoesNotExist:
        return Response(
            {'error': 'Issue report not found'},
            status=status.HTTP_404_NOT_FOUND,
        )

    if request.method == 'GET':
        serializer = IssueReportSerializer(report)
        return Response(serializer.data)

    new_status = request.data.get('status')
    if new_status not in dict(IssueReport.STATUS_CHOICES):
        return Response(
            {'error': 'Invalid status. Use open, acknowledged, or resolved.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    report.status = new_status
    report.save(update_fields=['status'])
    serializer = IssueReportSerializer(report)
    return Response(serializer.data)

class MaintenanceTemplateListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/maintenance-templates/      — list all maintenance templates
    POST /api/maintenance-templates/      — create a new maintenance template
    """
    serializer_class = MaintenanceTemplateSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return MaintenanceTemplate.objects.filter(owner=self.request.user)

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)

class MaintenanceTemplateDetailView(generics.RetrieveUpdateDestroyAPIView):
    """
    GET    /api/maintenance-templates/<id>/  — detail of one template
    PATCH  /api/maintenance-templates/<id>/  — partial update
    DELETE /api/maintenance-templates/<id>/  — remove a template
    """
    serializer_class = MaintenanceTemplateSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return MaintenanceTemplate.objects.filter(owner=self.request.user)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def apply_maintenance_template(request, pk):
    """
    POST /api/maintenance-templates/<id>/apply/
    Body: {"vehicle_ids": [1, 2, 3]} or {"vehicle_type": "ambulance"}
    
    Applies a maintenance template to specific vehicles or all vehicles of a type.
    Creates MaintenanceRecord for each targeted vehicle using the template's settings.
    """
    from datetime import timedelta
    
    try:
        template = MaintenanceTemplate.objects.get(pk=pk, owner=request.user)
    except MaintenanceTemplate.DoesNotExist:
        return Response(
            {'error': 'Template not found'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicle_ids = request.data.get('vehicle_ids', [])
    vehicle_type = request.data.get('vehicle_type', None)

    # Determine target vehicles
    vehicles_query = Vehicle.objects.filter(owner=request.user)
    
    if vehicle_ids:
        vehicles = vehicles_query.filter(pk__in=vehicle_ids)
    elif vehicle_type:
        vehicles = vehicles_query.filter(vehicle_type=vehicle_type)
    else:
        return Response(
            {'error': 'Provide either vehicle_ids or vehicle_type'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    if not vehicles.exists():
        return Response(
            {'error': 'No vehicles found matching criteria'},
            status=status.HTTP_404_NOT_FOUND,
        )

    # Calculate due date
    today = timezone.now().date()
    due_date = today
    if template.recurrence_days:
        due_date = today + timedelta(days=template.recurrence_days)
    else:
        # If only km-based, set due date to today (will be triggered by mileage)
        due_date = today

    # Create maintenance records for each vehicle
    created_count = 0
    for vehicle in vehicles:
        MaintenanceRecord.objects.create(
            vehicle=vehicle,
            maintenance_type=template.maintenance_type,
            description=template.description,
            due_date=due_date,
            recurrence_days=template.recurrence_days,
            recurrence_km=template.recurrence_km,
            owner=request.user,
        )
        created_count += 1

    return Response({
        'message': f'Applied template to {created_count} vehicle(s)',
        'created_count': created_count,
    }, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_trip_history(request):
    """
    GET /api/drivers/me/trip-history/
    Returns completed and cancelled trips for the driver's assigned vehicle(s).
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicles = driver.assigned_vehicles.all()
    dispatches = (
        DispatchRequest.objects
        .filter(assigned_vehicle__in=vehicles, status__in=['completed', 'cancelled', 'rejected'])
        .select_related('assigned_vehicle')
        .order_by('-created_at')
    )

    history = []
    for dispatch in dispatches:
        history.append({
            'id': dispatch.id,
            'vehicle_name': dispatch.assigned_vehicle.name if dispatch.assigned_vehicle else None,
            'vehicle_type': dispatch.assigned_vehicle.vehicle_type if dispatch.assigned_vehicle else None,
            'number_plate': dispatch.assigned_vehicle.number_plate if dispatch.assigned_vehicle else None,
            'status': dispatch.status,
            'created_at': dispatch.created_at.isoformat(),
            'assigned_at': dispatch.assigned_at.isoformat() if dispatch.assigned_at else None,
            'accepted_at': dispatch.accepted_at.isoformat() if dispatch.accepted_at else None,
            'en_route_at': dispatch.en_route_at.isoformat() if dispatch.en_route_at else None,
            'arrived_at': dispatch.arrived_at.isoformat() if dispatch.arrived_at else None,
            'completed_at': dispatch.completed_at.isoformat() if dispatch.completed_at else None,
            'cancelled_at': None,
            'distance_km': dispatch.distance_km,
            'duration_min': dispatch.duration_min,
            'trip_duration_seconds': dispatch.trip_duration_seconds,
            'response_time_seconds': dispatch.response_time_seconds,
            'request_lat': dispatch.request_lat,
            'request_lng': dispatch.request_lng,
        })

    return Response(history)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_notifications(request):
    """
    GET /api/drivers/me/notifications/
    Returns recent notifications for the driver.
    Includes assigned trips and admin alerts.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicles = driver.assigned_vehicles.all()
    
    # Get recent dispatches for the driver's vehicles (assigned, accepted, en_route, arrived)
    recent_dispatches = (
        DispatchRequest.objects
        .filter(assigned_vehicle__in=vehicles, status__in=['assigned', 'accepted', 'en_route', 'arrived'])
        .select_related('assigned_vehicle')
        .order_by('-created_at')[:20]
    )

    notifications = []
    for dispatch in recent_dispatches:
        notifications.append({
            'id': f'dispatch_{dispatch.id}',
            'type': 'trip',
            'title': f'Trip {dispatch.get_status_display()}',
            'message': f'Vehicle {dispatch.assigned_vehicle.name if dispatch.assigned_vehicle else "Unknown"} - {dispatch.vehicle_type}',
            'status': dispatch.status,
            'timestamp': dispatch.created_at.isoformat(),
            'read': False,
            'dispatch_id': dispatch.id,
        })

    # Get recent issue reports for the driver
    recent_issues = (
        IssueReport.objects
        .filter(driver=driver)
        .order_by('-created_at')[:10]
    )

    for issue in recent_issues:
        notifications.append({
            'id': f'issue_{issue.id}',
            'type': 'issue',
            'title': 'Issue Report Update',
            'message': issue.description[:100] + ('...' if len(issue.description) > 100 else ''),
            'status': issue.status,
            'timestamp': issue.created_at.isoformat(),
            'read': False,
        })

    # Sort by timestamp descending
    notifications.sort(key=lambda x: x['timestamp'], reverse=True)

    return Response(notifications)

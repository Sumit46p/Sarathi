from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance
from django.contrib.auth.models import User
from django.db.models import Q, ExpressionWrapper, DurationField, Count, Sum, Avg, F, Value, CharField
from django.db.models.functions import TruncDate, Coalesce
from django.utils import timezone
from .osrm import get_route_distance
import threading
import math


def get_org_user_ids(user):
    """
    Return a list of User IDs that belong to the same organization as *user*.

    All admin/staff accounts whose Profile.organization_name matches the
    requesting user's org name are considered part of the same organization.
    This lets multiple admin accounts share the same pool of drivers,
    vehicles, and other resources.

    Falls back to [user.id] when no profile is found so existing per-user
    data is always visible.
    """
    from accounts.models import Profile
    try:
        org_name = user.profile.organization_name
    except Exception:
        return [user.id]

    if not org_name or org_name == 'Default Org':
        return [user.id]

    ids = list(
        Profile.objects
        .filter(organization_name__iexact=org_name)
        .values_list('user_id', flat=True)
    )
    # Always include the current user even if their profile is oddly configured
    if user.id not in ids:
        ids.append(user.id)
    return ids

from .models import Vehicle, DispatchRequest, Driver, MaintenanceRecord, MaintenanceTemplate, IssueReport, Notification, EmergencyRequest, FuelEntry, FuelLog, FuelPrice, LocationRecord, DrivingEvent
from .serializers import (
    VehicleSerializer,
    LocationUpdateSerializer,
    NearestVehicleSerializer,
    FuelPriceSerializer,
    DispatchRequestInputSerializer,
    MaintenanceRecordSerializer,
    DispatchRequestSerializer,
    DriverSerializer,
    AssignDriverSerializer,
    DriverMeSerializer,
    IssueReportSerializer,
    MaintenanceTemplateSerializer,
    EmergencyRequestSerializer,
    EmergencyRequestCreateSerializer,
    FuelEntrySerializer,
    FuelLogSerializer,
    FuelLogCreateSerializer,
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


def _bearing_deg(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle initial bearing from point 1 to point 2, in degrees [0, 360)."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_lng = math.radians(lng2 - lng1)
    y = math.sin(d_lng) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(d_lng)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


# Thresholds for server-side harsh-event detection from GPS breadcrumbs.
# With coarse (4-5s) fixes only strong events are visible; the Flutter app
# reports phone-accelerometer events for finer fidelity.
HARSH_ACCEL_MS2 = 2.5
HARSH_BRAKE_MS2 = -2.5
HARSH_TURN_DEG = 30
MIN_EVENT_SPEED_KMH = 8.0


def detect_driving_events(vehicle, dispatch, record):
    """Detect harsh acceleration/braking/turns from consecutive GPS fixes.

    Called after a new :class:`LocationRecord` is stored. Compares the latest
    fix against the two previous ones:
      - longitudinal acceleration = (v2 - v1) / dt  (m/s^2)
      - turning = heading change across the last two segments (degrees)

    Creates a :class:`DrivingEvent` for every metric that exceeds its
    threshold while the vehicle is moving.
    """
    if record.speed_kmh < MIN_EVENT_SPEED_KMH:
        return

    history = list(
        LocationRecord.objects
        .filter(vehicle=vehicle, id__lte=record.id)
        .order_by('-id')[:3]
    )
    if len(history) < 3:
        # Not enough consecutive fixes yet (need at least 3 for turning).
        history.sort(key=lambda r: r.id)
        if len(history) < 2:
            return
        prev = history[-2]
        dt = (record.recorded_at - prev.recorded_at).total_seconds()
        if dt <= 0:
            return
        accel = (record.speed_kmh - prev.speed_kmh) / 3.6 / dt
        _record_events(vehicle, dispatch, record, accel=accel, turn_deg=0.0)
        return

    newest, prev, prev2 = history
    dt = (newest.recorded_at - prev.recorded_at).total_seconds()
    if dt <= 0:
        return
    accel = (newest.speed_kmh - prev.speed_kmh) / 3.6 / dt

    bearing1 = _bearing_deg(prev2.location.y, prev2.location.x, prev.location.y, prev.location.x)
    bearing2 = _bearing_deg(prev.location.y, prev.location.x, newest.location.y, newest.location.x)
    turn = abs((bearing2 - bearing1 + 180) % 360 - 180)

    _record_events(vehicle, dispatch, record, accel=accel, turn_deg=turn)


def _record_events(vehicle, dispatch, record, accel: float, turn_deg: float) -> None:
    """Persist DrivingEvent rows for metrics exceeding their thresholds."""
    driver = vehicle.driver
    now = timezone.now()

    if accel > HARSH_ACCEL_MS2:
        DrivingEvent.objects.create(
            vehicle=vehicle, driver=driver, dispatch=dispatch,
            event_type='harsh_accel',
            severity=round(accel / HARSH_ACCEL_MS2, 2),
            speed_kmh=record.speed_kmh,
            value=round(accel, 2),
            created_at=now,
        )
    if accel < HARSH_BRAKE_MS2:
        DrivingEvent.objects.create(
            vehicle=vehicle, driver=driver, dispatch=dispatch,
            event_type='harsh_brake',
            severity=round(abs(accel) / abs(HARSH_BRAKE_MS2), 2),
            speed_kmh=record.speed_kmh,
            value=round(accel, 2),
            created_at=now,
        )
    if turn_deg > HARSH_TURN_DEG and record.speed_kmh >= MIN_EVENT_SPEED_KMH:
        DrivingEvent.objects.create(
            vehicle=vehicle, driver=driver, dispatch=dispatch,
            event_type='harsh_turn',
            severity=round(turn_deg / HARSH_TURN_DEG, 2),
            speed_kmh=record.speed_kmh,
            value=round(turn_deg, 2),
            created_at=now,
        )


DRIVER_SCORE_WINDOW_DAYS = 30
DRIVER_SCORE_WEIGHTS = {
    'harsh_accel': 2,
    'harsh_brake': 3,
    'harsh_turn': 4,
}


def compute_driver_score(driver, days: int = DRIVER_SCORE_WINDOW_DAYS):
    """0-100 driver safety score over the rolling window.

    Starts at 100 and subtracts weighted penalties per harsh-driving event
    (clamped at 0). Returns (score, breakdown_by_type, total_events).
    """
    cutoff = timezone.now() - timezone.timedelta(days=days)
    breakdown = {key: 0 for key in DRIVER_SCORE_WEIGHTS}
    total = 0
    rows = (
        DrivingEvent.objects
        .filter(driver=driver, created_at__gte=cutoff)
        .values('event_type')
        .annotate(count=Count('id'))
    )
    for row in rows:
        breakdown[row['event_type']] = row['count']
        total += row['count']
    penalty = sum(breakdown[k] * w for k, w in DRIVER_SCORE_WEIGHTS.items())
    return max(0, 100 - penalty), breakdown, total


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


def _auto_create_next_record(record: MaintenanceRecord) -> MaintenanceRecord | None:
    """
    Automatically creates the next recurring maintenance record when a
    maintenance record is marked completed.

    Recurrence rules:
    - recurrence_days: next due_date = completion date + N days
    - recurrence_km:   next due_date = today (mileage trigger will drive it)

    Returns the newly created MaintenanceRecord, or None if the record has
    no recurrence rule (one-off maintenance).
    """
    from datetime import timedelta

    if not record.recurrence_days and not record.recurrence_km:
        return None

    today = timezone.now().date()
    next_due = today
    if record.recurrence_days:
        next_due = today + timedelta(days=record.recurrence_days)

    next_record = MaintenanceRecord.objects.create(
        vehicle=record.vehicle,
        maintenance_type=record.maintenance_type,
        description=record.description,
        due_date=next_due,
        recurrence_days=record.recurrence_days,
        recurrence_km=record.recurrence_km,
        owner=record.owner,
    )
    return next_record


class VehicleListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/vehicles/      — list all vehicles with current location
    POST /api/vehicles/      — create a new vehicle (for testing without admin)
    """
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Vehicle.objects.filter(owner__in=get_org_user_ids(self.request.user))

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
        return Driver.objects.filter(owner__in=get_org_user_ids(self.request.user))

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
        return Driver.objects.filter(owner__in=get_org_user_ids(self.request.user))

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
    return safe_route_info(vehicle, dispatch, deadline)['geometry']


def safe_route_info(vehicle, dispatch, deadline=3.0):
    """Best-effort live route info (geometry, road distance, ETA) from the
    vehicle's current location to the dispatch request.

    Like :func:`safe_route_geometry`, OSRM runs in a separate thread with a
    hard deadline so an unreachable router can never block the API response.
    Returns None for each field on any failure or timeout.
    """
    if vehicle.location is None:
        return {'geometry': None, 'distance_km': None, 'duration_min': None}

    result = {'geometry': None, 'distance_km': None, 'duration_min': None}

    def _compute():
        try:
            distance_km, duration_min, geometry = get_route_distance(
                vehicle.location.y, vehicle.location.x,
                dispatch.request_lat, dispatch.request_lng,
            )
            result['distance_km'] = distance_km
            result['duration_min'] = duration_min
            result['geometry'] = geometry
        except Exception:
            pass

    worker = threading.Thread(target=_compute, daemon=True)
    worker.start()
    worker.join(timeout=deadline)
    if worker.is_alive():
        return {'geometry': None, 'distance_km': None, 'duration_min': None}
    return result


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def active_dispatch(request):
    """Return the owner's latest active dispatch with live route geometry."""
    dispatch = (
        DispatchRequest.objects
        .select_related('assigned_vehicle')
        .filter(
            assigned_vehicle__owner__in=get_org_user_ids(request.user),
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
    route = safe_route_info(dispatch.assigned_vehicle, dispatch)
    data['geometry'] = route['geometry']
    data['remaining_distance_km'] = route['distance_km']
    data['eta_min'] = route['duration_min']

    # Live progress = how much of the dispatch-time road distance has been
    # covered, based on the remaining road distance from the vehicle's
    # current location to the request.
    total_km = dispatch.distance_km
    if total_km and route['distance_km'] is not None and total_km > 0:
        progress = (1 - (route['distance_km'] / total_km)) * 100
        data['progress_percent'] = round(max(0.0, min(100.0, progress)), 1)
    else:
        data['progress_percent'] = None
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

# Statuses that mean a driver accepted the trip (used for acceptance-rate KPI).
ACCEPTED_DISPATCH_STATUSES = ['accepted', 'en_route', 'arrived', 'completed']


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


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def vehicle_dispatch(request, pk):
    """
    GET /api/vehicles/<pk>/dispatch/
    Returns the active dispatch for a specific vehicle with live route geometry.
    """
    try:
        vehicle = Vehicle.objects.get(pk=pk, owner__in=get_org_user_ids(request.user))
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
        vehicle = Vehicle.objects.get(pk=pk, owner__in=get_org_user_ids(request.user))
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
    speed_kmh = serializer.validated_data.get('speed_kmh')

    # Calculate distance from previous location if it exists
    NOISE_THRESHOLD_METERS = 15
    distance_increment_km = 0
    now = timezone.now()
    prev_fix_at = vehicle.last_location_at

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
    vehicle.last_location_at = now
    vehicle.save(update_fields=['location', 'last_location_at', 'total_distance_km'])

    # Record a GPS breadcrumb for trip history / route playback. If the vehicle
    # is mid-dispatch the fix is attributed to that trip so the route can be
    # replayed afterwards. Speed is derived from the fix interval when the
    # client did not report one.
    active_dispatch = vehicle.dispatch_requests.filter(
        status__in=ACTIVE_DISPATCH_STATUSES
    ).order_by('-created_at').first()
    derived_speed = 0.0
    if speed_kmh is None and distance_increment_km and prev_fix_at is not None:
        seconds = max(1.0, (now - prev_fix_at).total_seconds())
        derived_speed = distance_increment_km / (seconds / 3600)
    record = LocationRecord.objects.create(
        vehicle=vehicle,
        dispatch=active_dispatch,
        location=new_location,
        speed_kmh=speed_kmh if speed_kmh is not None else round(derived_speed, 1),
        recorded_at=now,
    )
    # Detect harsh-driving events from the breadcrumb stream (server-side
    # heuristics; the Flutter app reports accelerometer events for fidelity).
    detect_driving_events(vehicle, active_dispatch, record)

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
        vehicle = Vehicle.objects.get(pk=pk, owner__in=get_org_user_ids(request.user))
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
            driver = Driver.objects.get(pk=driver_id, owner__in=get_org_user_ids(request.user))
            vehicle.driver = driver
        except Driver.DoesNotExist:
            return Response(
                {'error': 'Driver not found or access denied'},
                status=status.HTTP_404_NOT_FOUND,
            )

    vehicle.save(update_fields=['driver'])
    # Recompute availability based on new driver assignment
    vehicle.recompute_availability()
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
        .filter(owner__in=get_org_user_ids(request.user), is_available=True, vehicle_type=vehicle_type)
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
    # Only select vehicles that have a driver assigned
    candidates = list(
        Vehicle.objects
        .filter(
            owner__in=get_org_user_ids(request.user),
            is_available=True,
            vehicle_type=vehicle_type,
            driver__isnull=False
        )
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

    # Create notification for the driver
    if nearest.driver and nearest.driver.user:
        Notification.objects.create(
            user=nearest.driver.user,
            notification_type='trip',
            title='New Trip Assigned',
            message=f'Vehicle {nearest.name} ({nearest.vehicle_type}) has been assigned a new trip.',
            related_dispatch=dispatch,
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
    
    For staff users (is_staff=True), returns records for their organization.
    For admin users, returns all records.
    """
    serializer_class = MaintenanceRecordSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return MaintenanceRecord.objects.filter(owner__in=get_org_user_ids(user))

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
        user = self.request.user
        return MaintenanceRecord.objects.filter(owner__in=get_org_user_ids(user))

    def perform_update(self, serializer):
        # Auto-set completed_at when completed is marked True
        completed = serializer.validated_data.get('completed', None)
        if completed:
            instance = serializer.save(completed_at=timezone.now())
            # Auto-create next recurring record if recurrence rules are set
            _auto_create_next_record(instance)
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
        owner__in=get_org_user_ids(request.user),
        due_date__range=[today, thirty_days_later]
    ).order_by('due_date')

    serializer = MaintenanceRecordSerializer(records, many=True)
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_maintenance_request(request):
    """
    POST /api/drivers/me/maintenance-request/
    Body (multipart/form-data):
      - description (text, optional)
      - image (file, optional)
    Allows a driver to submit a maintenance request to the admin.
    """
    description = request.data.get('description', '').strip()
    image = request.data.get('image') if 'image' in request.data else None

    if not description and not image:
        return Response(
            {'error': 'Please provide a description or image'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    # Get the driver's assigned vehicle
    try:
        driver = Driver.objects.get(user=request.user)
        vehicle = driver.assigned_vehicles.first()
    except Driver.DoesNotExist:
        vehicle = None

    # Create a pending maintenance record for the driver
    record = MaintenanceRecord.objects.create(
        vehicle=vehicle,
        maintenance_type='other',
        description=description or 'Maintenance request from driver',
        due_date=timezone.now().date(),
        completed=False,
        owner=request.user,
        image=image,
    )

    serializer = MaintenanceRecordSerializer(record)
    return Response(serializer.data, status=status.HTTP_201_CREATED)


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

    # Create notification for the driver
    Notification.objects.create(
        user=driver.user,
        notification_type='issue',
        title='Issue Report Submitted',
        message=description[:200],
        related_issue=report,
    )

    serializer = IssueReportSerializer(report, context={'request': request})
    return Response(serializer.data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def issue_report_list(request):
    """
    GET /api/issues/
    Returns all issue reports for the current owner (org-scoped),
    sorted newest first.
    """
    reports = IssueReport.objects.filter(driver__owner__in=get_org_user_ids(request.user)).select_related('driver')
    serializer = IssueReportSerializer(reports, many=True, context={'request': request})
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
        report = IssueReport.objects.get(pk=pk, driver__owner__in=get_org_user_ids(request.user))
    except IssueReport.DoesNotExist:
        return Response(
            {'error': 'Issue report not found'},
            status=status.HTTP_404_NOT_FOUND,
        )

    if request.method == 'GET':
        serializer = IssueReportSerializer(report, context={'request': request})
        return Response(serializer.data)

    new_status = request.data.get('status')
    if new_status not in dict(IssueReport.STATUS_CHOICES):
        return Response(
            {'error': 'Invalid status. Use open, acknowledged, or resolved.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    report.status = new_status
    report.save(update_fields=['status'])
    serializer = IssueReportSerializer(report, context={'request': request})
    return Response(serializer.data)

class MaintenanceTemplateListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/maintenance-templates/      — list all maintenance templates
    POST /api/maintenance-templates/      — create a new maintenance template
    """
    serializer_class = MaintenanceTemplateSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return MaintenanceTemplate.objects.filter(owner__in=get_org_user_ids(self.request.user))

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
        return MaintenanceTemplate.objects.filter(owner__in=get_org_user_ids(self.request.user))

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
        template = MaintenanceTemplate.objects.get(pk=pk, owner__in=get_org_user_ids(request.user))
    except MaintenanceTemplate.DoesNotExist:
        return Response(
            {'error': 'Template not found'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicle_ids = request.data.get('vehicle_ids', [])
    vehicle_type = request.data.get('vehicle_type', None)

    # Determine target vehicles
    vehicles_query = Vehicle.objects.filter(owner__in=get_org_user_ids(request.user))
    
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
        .annotate(point_count=Count('location_records'))
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
            'point_count': dispatch.point_count,
        })

    return Response(history)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def trip_list(request):
    """
    GET /api/trips/
    Org-scoped list of finished dispatches (completed/cancelled/rejected) with
    GPS breadcrumb counts, backing the Trip History / route playback tab.
    """
    dispatches = (
        DispatchRequest.objects
        .filter(
            assigned_vehicle__owner__in=get_org_user_ids(request.user),
            status__in=['completed', 'cancelled', 'rejected'],
        )
        .select_related('assigned_vehicle', 'assigned_vehicle__driver')
        .annotate(point_count=Count('location_records'))
        .order_by('-created_at')
    )

    trips = []
    for dispatch in dispatches:
        veh = dispatch.assigned_vehicle
        trips.append({
            'id': dispatch.id,
            'status': dispatch.status,
            'vehicle_name': veh.name if veh else None,
            'vehicle_type': veh.vehicle_type if veh else None,
            'number_plate': veh.number_plate if veh else None,
            'driver_name': veh.driver.name if veh and veh.driver else None,
            'created_at': dispatch.created_at.isoformat(),
            'assigned_at': dispatch.assigned_at.isoformat() if dispatch.assigned_at else None,
            'completed_at': dispatch.completed_at.isoformat() if dispatch.completed_at else None,
            'distance_km': dispatch.distance_km,
            'duration_min': dispatch.duration_min,
            'trip_duration_seconds': dispatch.trip_duration_seconds,
            'request_lat': dispatch.request_lat,
            'request_lng': dispatch.request_lng,
            'point_count': dispatch.point_count,
        })

    return Response(trips)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def trip_playback(request, pk):
    """
    GET /api/trips/<dispatch_id>/playback/
    Returns time-ordered GPS breadcrumbs for a dispatch so the route can be
    replayed on the map. Accessible to the org admin or the vehicle's
    assigned driver (for the driver app's trip history).
    """
    try:
        dispatch = DispatchRequest.objects.select_related(
            'assigned_vehicle', 'assigned_vehicle__driver'
        ).get(pk=pk)
    except DispatchRequest.DoesNotExist:
        return Response(
            {'error': 'Trip not found or access denied'},
            status=status.HTTP_404_NOT_FOUND,
        )

    veh = dispatch.assigned_vehicle
    is_owner = veh is not None and veh.owner_id in get_org_user_ids(request.user)
    is_assigned_driver = (
        veh is not None and veh.driver is not None
        and veh.driver.user is not None and veh.driver.user_id == request.user.id
    )
    if not (is_owner or is_assigned_driver):
        return Response(
            {'error': 'Trip not found or access denied'},
            status=status.HTTP_404_NOT_FOUND,
        )

    records = dispatch.location_records.order_by('recorded_at')
    points = [{
        'lat': record.location.y,
        'lng': record.location.x,
        'speed_kmh': record.speed_kmh,
        'recorded_at': record.recorded_at.isoformat(),
    } for record in records]

    veh = dispatch.assigned_vehicle
    return Response({
        'dispatch_id': dispatch.id,
        'status': dispatch.status,
        'vehicle_name': veh.name if veh else None,
        'number_plate': veh.number_plate if veh else None,
        'request_lat': dispatch.request_lat,
        'request_lng': dispatch.request_lng,
        'points': points,
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_score(request, pk):
    """
    GET /api/drivers/<driver_id>/score/
    Org-scoped driver safety score (0-100) from harsh-driving events in the
    rolling 30-day window, plus per-type event counts.
    """
    try:
        driver = Driver.objects.get(pk=pk, owner__in=get_org_user_ids(request.user))
    except Driver.DoesNotExist:
        return Response(
            {'error': 'Driver not found or access denied'},
            status=status.HTTP_404_NOT_FOUND,
        )

    score, breakdown, total = compute_driver_score(driver)
    return Response({
        'driver_id': driver.id,
        'name': driver.name,
        'score': score,
        'events': breakdown,
        'total_events': total,
        'window_days': DRIVER_SCORE_WINDOW_DAYS,
    })


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


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def create_emergency_request(request):
    """
    POST /api/emergency/requests/
    Body: {
      "emergency_type": "medical|accident|breakdown|other",
      "description": "...",
      "location": {"lat": ..., "lng": ...} or null,
      "image": <file> (optional)
    }
    Creates an emergency SOS request from the driver.
    """
    serializer = EmergencyRequestCreateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    
    emergency = serializer.save(user=request.user)
    
    # Create notification for all admins of the organization
    from django.contrib.auth.models import User
    from accounts.models import Profile
    
    # Get all admin users in the same organization
    driver = Driver.objects.filter(user=request.user).first()
    if driver:
        org_name = None
        try:
            profile = Profile.objects.get(user=request.user)
            org_name = profile.organization_name
        except Profile.DoesNotExist:
            pass
        
        if org_name:
            admin_users = User.objects.filter(
                profile__organization_name=org_name,
                is_staff=True,
            )
            driver_name = f"User {request.user.username}"
            if hasattr(request.user, 'driver'):
                if request.user.driver.assigned_vehicle_id:
                    driver_name = f"Vehicle #{request.user.driver.assigned_vehicle_id}"
                else:
                    driver_name = f"Driver {request.user.driver.name}"
                    
            for admin in admin_users:
                Notification.objects.create(
                    user=admin,
                    notification_type='admin',
                    title=f'Emergency: {emergency.get_emergency_type_display()}',
                    message=f'Emergency request from {driver_name}: {emergency.description or "No description"}',
                )
    
    return Response(EmergencyRequestSerializer(emergency, context={'request': request}).data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def emergency_request_list(request):
    """
    GET /api/emergency/requests/
    Returns all emergency requests for the current admin's organization.
    Supports filtering by status via ?status=pending|dispatched|resolved|cancelled
    """
    from django.contrib.auth.models import User
    from accounts.models import Profile
    
    # Get all drivers belonging to the same org as the requesting admin
    org_ids = get_org_user_ids(request.user)
    drivers = Driver.objects.filter(owner__in=org_ids).select_related('user')
    driver_user_ids = [d.user.id for d in drivers if d.user_id is not None]

    # Get emergency requests from those driver users
    status_filter = request.query_params.get('status')
    queryset = EmergencyRequest.objects.filter(
        user__in=driver_user_ids
    ).select_related('user', 'assigned_vehicle')
    
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    
    queryset = queryset.order_by('-created_at')
    
    serializer = EmergencyRequestSerializer(queryset, many=True, context={'request': request})
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def emergency_request_dispatch(request, pk):
    """
    POST /api/emergency/requests/<id>/dispatch/
    Body: {"vehicle_id": 123}
    Dispatches the nearest available vehicle to the emergency request.
    """
    try:
        emergency = EmergencyRequest.objects.get(pk=pk)
    except EmergencyRequest.DoesNotExist:
        return Response(
            {'error': 'Emergency request not found'},
            status=status.HTTP_404_NOT_FOUND,
        )
    
    if emergency.status != 'pending':
        return Response(
            {'error': f'Emergency request is already {emergency.status}'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    
    vehicle_id = request.data.get('vehicle_id')
    if not vehicle_id:
        return Response(
            {'error': 'vehicle_id is required'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    
    try:
        vehicle = Vehicle.objects.get(pk=vehicle_id, is_available=True)
    except Vehicle.DoesNotExist:
        return Response(
            {'error': 'Vehicle not found or not available'},
            status=status.HTTP_404_NOT_FOUND,
        )
    
    # Update emergency request
    emergency.status = 'dispatched'
    emergency.assigned_vehicle = vehicle
    emergency.save(update_fields=['status', 'assigned_vehicle', 'updated_at'])
    
    # Mark vehicle as unavailable
    vehicle.is_available = False
    vehicle.save(update_fields=['is_available'])
    
    # Create notification for the user who requested help
    Notification.objects.create(
        user=emergency.user,
        notification_type='admin',
        title='Emergency Help Dispatched',
        message=f'Help is on the way! Vehicle {vehicle.name} ({vehicle.vehicle_type}) has been dispatched to your location.',
    )
    
    serializer = EmergencyRequestSerializer(emergency, context={'request': request})
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def emergency_request_resolve(request, pk):
    """
    POST /api/emergency/requests/<id>/resolve/
    Marks an emergency request as resolved.
    """
    try:
        emergency = EmergencyRequest.objects.get(pk=pk)
    except EmergencyRequest.DoesNotExist:
        return Response(
            {'error': 'Emergency request not found'},
            status=status.HTTP_404_NOT_FOUND,
        )
    
    if emergency.status == 'resolved':
        return Response(
            {'error': 'Emergency request is already resolved'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    
    # Free up the vehicle if one was assigned
    if emergency.assigned_vehicle:
        emergency.assigned_vehicle.is_available = True
        emergency.assigned_vehicle.save(update_fields=['is_available'])
    
    emergency.status = 'resolved'
    emergency.resolved_at = timezone.now()
    emergency.save(update_fields=['status', 'resolved_at', 'updated_at'])
    
    # Notify the user
    Notification.objects.create(
        user=emergency.user,
        notification_type='system',
        title='Emergency Resolved',
        message='Your emergency request has been marked as resolved. Stay safe!',
    )
    
    serializer = EmergencyRequestSerializer(emergency, context={'request': request})
    return Response(serializer.data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def emergency_request_detail(request, pk):
    """
    GET /api/emergency/requests/<id>/
    Returns details of a specific emergency request.
    """
    try:
        emergency = EmergencyRequest.objects.get(pk=pk)
    except EmergencyRequest.DoesNotExist:
        return Response(
            {'error': 'Emergency request not found'},
            status=status.HTTP_404_NOT_FOUND,
        )
    
    serializer = EmergencyRequestSerializer(emergency, context={'request': request})
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def mark_emergency_notifications_read(request):
    """
    POST /api/emergency/notifications/mark-read/
    Marks all unread emergency-related notifications as read for the current user.
    """
    from accounts.models import Profile
    
    try:
        profile = Profile.objects.get(user=request.user)
    except Profile.DoesNotExist:
        return Response(
            {'error': 'No profile found'},
            status=status.HTTP_404_NOT_FOUND,
        )
    
    notifications = Notification.objects.filter(
        user=request.user,
        is_read=False,
        title__startswith='Emergency:'
    )
    
    count = notifications.count()
    notifications.update(is_read=True)
    
    return Response({'marked_read': count})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def unread_emergency_count(request):
    """
    GET /api/emergency/notifications/unread-count/
    Returns the count of unread emergency notifications for the current user.
    """
    count = Notification.objects.filter(
        user=request.user,
        is_read=False,
        title__startswith='Emergency:'
    ).count()
    
    return Response({'unread_count': count})


# ---------------------------------------------------------------------------
# Fuel Entry Views
# ---------------------------------------------------------------------------

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def fuel_entry_list_create(request):
    """
    GET  /api/fuel/  — Admin: list all entries for their org's vehicles.
                       Driver: list their own fuel entries.
    POST /api/fuel/  — Driver: create a new fuel entry.
    """
    # Check if driver
    driver = None
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        pass

    if request.method == 'GET':
        if driver:
            entries = FuelEntry.objects.filter(driver=driver).select_related('vehicle', 'driver')
        else:
            # Admin: show entries where this admin owns the vehicle OR manages the driver.
            # This ensures entries are visible even if a vehicle was mis-assigned.
            if request.user.is_staff:
                entries = FuelEntry.objects.all().select_related('vehicle', 'driver')
            else:
                entries = FuelEntry.objects.filter(
                    Q(vehicle__owner__in=get_org_user_ids(request.user)) | Q(driver__owner__in=get_org_user_ids(request.user))
                ).distinct().select_related('vehicle', 'driver')
        serializer = FuelEntrySerializer(entries, many=True)
        return Response(serializer.data)

    # POST — driver creates entry
    if not driver:
        return Response(
            {'error': 'Only drivers can create fuel entries'},
            status=status.HTTP_403_FORBIDDEN,
        )

    # Resolve the vehicle automatically from driver profile
    vehicle = driver.assigned_vehicles.first()
    if not vehicle:
        return Response(
            {'error': 'No vehicle is assigned to you'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    data = request.data.copy()
    data['driver'] = driver.id
    data['vehicle'] = vehicle.id

    # Auto-calculate total_cost if not provided
    if 'total_cost' not in data or not data['total_cost']:
        try:
            data['total_cost'] = float(data['liters']) * float(data['cost_per_liter'])
        except (KeyError, ValueError, TypeError):
            pass

    serializer = FuelEntrySerializer(data=data)
    if serializer.is_valid():
        entry = serializer.save()
        return Response(FuelEntrySerializer(entry).data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['GET', 'DELETE'])
@permission_classes([IsAuthenticated])
def fuel_entry_detail(request, pk):
    """
    GET    /api/fuel/<id>/  — Retrieve a single fuel entry.
    DELETE /api/fuel/<id>/  — Driver deletes their own entry; admin can delete any.
    """
    try:
        entry = FuelEntry.objects.select_related('vehicle', 'driver').get(pk=pk)
    except FuelEntry.DoesNotExist:
        return Response({'error': 'Fuel entry not found'}, status=status.HTTP_404_NOT_FOUND)

    # Permission: driver can only see/delete own entries; admin can do anything
    try:
        driver = Driver.objects.get(user=request.user)
        if entry.driver != driver:
            return Response({'error': 'Not authorised'}, status=status.HTTP_403_FORBIDDEN)
    except Driver.DoesNotExist:
        # Is admin — check vehicle ownership
        if entry.vehicle.owner != request.user:
            return Response({'error': 'Not authorised'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'GET':
        return Response(FuelEntrySerializer(entry).data)

    # DELETE
    entry.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------------------
# Driver Maintenance Request Delete
# ---------------------------------------------------------------------------

@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def driver_maintenance_request_delete(request, pk):
    """
    DELETE /api/drivers/me/maintenance-request/<id>/
    Allows a driver to delete one of their own maintenance records.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    try:
        record = MaintenanceRecord.objects.get(pk=pk, driver=driver)
    except MaintenanceRecord.DoesNotExist:
        return Response({'error': 'Record not found'}, status=status.HTTP_404_NOT_FOUND)

    record.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------------------
# Driver Maintenance Views
# ---------------------------------------------------------------------------

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_maintenance_list(request):
    """
    GET /api/drivers/me/maintenance/
    Returns all maintenance records for the driver's assigned vehicle(s).
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicles = driver.assigned_vehicles.all()
    records = (
        MaintenanceRecord.objects
        .filter(vehicle__in=vehicles)
        .select_related('vehicle', 'completed_by')
        .order_by('due_date')
    )
    serializer = MaintenanceRecordSerializer(records, many=True, context={'request': request})
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_maintenance_complete(request, pk):
    """
    POST /api/drivers/me/maintenance/<id>/complete/
    Body (multipart/form-data):
      - proof_image (file, optional)
      - completion_notes (text, optional)
    Marks a maintenance record as completed by the driver.
    Auto-creates the next recurring record if recurrence rules are set.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicles = driver.assigned_vehicles.all()
    try:
        record = MaintenanceRecord.objects.get(pk=pk, vehicle__in=vehicles)
    except MaintenanceRecord.DoesNotExist:
        return Response(
            {'error': 'Maintenance record not found'},
            status=status.HTTP_404_NOT_FOUND,
        )

    if record.completed:
        return Response(
            {'error': 'Record is already completed'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    record.completed = True
    record.completed_at = timezone.now()
    record.completed_by = driver

    proof_image = request.data.get('proof_image') if 'proof_image' in request.data else None
    if proof_image:
        record.proof_image = proof_image

    completion_notes = request.data.get('completion_notes', '').strip()
    if completion_notes:
        record.completion_notes = completion_notes

    record.save()

    # Auto-create next recurring record
    _auto_create_next_record(record)

    serializer = MaintenanceRecordSerializer(record, context={'request': request})
    return Response(serializer.data)


# ---------------------------------------------------------------------------
# Fuel Log Views
# ---------------------------------------------------------------------------

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_fuel_log_create(request):
    """
    POST /api/drivers/me/fuel-log/
    Body (multipart/form-data):
      - amount (decimal, required)  — total fuel cost in NPR
      - odometer_reading (decimal, optional)
      - receipt_image (file, REQUIRED) — photo of the fuel receipt
      - notes (text, optional)

    Creates a FuelLog bound to the driver's assigned vehicle.
    The admin-facing list endpoint (/api/fuel-logs/ filters by
    vehicle__owner) will then show it in the dashboard's Fuel Logs tab.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {'error': 'No driver profile is linked to this user account'},
            status=status.HTTP_404_NOT_FOUND,
        )

    vehicle = driver.assigned_vehicles.first()
    if not vehicle:
        return Response(
            {'error': 'No vehicle is assigned to you'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    serializer = FuelLogCreateSerializer(data=request.data)
    if serializer.is_valid():
        log = serializer.save(driver=driver, vehicle=vehicle)
        return Response(
            FuelLogSerializer(log, context={'request': request}).data,
            status=status.HTTP_201_CREATED,
        )
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def fuel_log_list_create(request):
    """
    GET  /api/fuel-logs/  — Admin: list all fuel logs for their org's vehicles.
                            Driver: list their own fuel logs.
    POST /api/fuel-logs/  — Driver: create a new fuel log entry.
    """
    driver = None
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        pass

    if request.method == 'GET':
        if driver:
            logs = FuelLog.objects.filter(driver=driver).select_related('vehicle', 'driver')
        else:
            logs = FuelLog.objects.filter(
                vehicle__owner=request.user
            ).select_related('vehicle', 'driver')
        serializer = FuelLogSerializer(logs, many=True, context={'request': request})
        return Response(serializer.data)

    # POST — driver creates entry
    if not driver:
        return Response(
            {'error': 'Only drivers can create fuel log entries'},
            status=status.HTTP_403_FORBIDDEN,
        )

    vehicle = driver.assigned_vehicles.first()
    if not vehicle:
        return Response(
            {'error': 'No vehicle is assigned to you'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    serializer = FuelLogCreateSerializer(data=request.data)
    if serializer.is_valid():
        log = serializer.save(driver=driver, vehicle=vehicle)
        return Response(
            FuelLogSerializer(log, context={'request': request}).data,
            status=status.HTTP_201_CREATED,
        )
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['GET', 'DELETE'])
@permission_classes([IsAuthenticated])
def fuel_log_detail(request, pk):
    """
    GET    /api/fuel-logs/<id>/  — Retrieve a single fuel log.
    DELETE /api/fuel-logs/<id>/  — Driver deletes their own entry; admin can delete any.
    """
    try:
        log = FuelLog.objects.select_related('vehicle', 'driver').get(pk=pk)
    except FuelLog.DoesNotExist:
        return Response({'error': 'Fuel log not found'}, status=status.HTTP_404_NOT_FOUND)

    try:
        driver = Driver.objects.get(user=request.user)
        if log.driver != driver:
            return Response({'error': 'Not authorised'}, status=status.HTTP_403_FORBIDDEN)
    except Driver.DoesNotExist:
        if log.vehicle.owner != request.user:
            return Response({'error': 'Not authorised'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'GET':
        return Response(FuelLogSerializer(log, context={'request': request}).data)

    log.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


# ── Dashboard Stats Endpoints ────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def dispatch_stats(request):
    """
    GET /api/dispatch/stats/
    Dispatch counts grouped by status for the last 30 days,
    plus a daily breakdown for charting. Owner-scoped.
    """
    from django.db.models import Count
    from django.db.models.functions import TruncDate
    import datetime

    owner = request.user
    thirty_days_ago = timezone.now() - datetime.timedelta(days=30)

    qs = DispatchRequest.objects.filter(
        assigned_vehicle__owner=owner,
        created_at__gte=thirty_days_ago,
    )

    status_counts = qs.values('status').annotate(count=Count('id'))
    status_map = {row['status']: row['count'] for row in status_counts}

    daily = (
        qs.annotate(day=TruncDate('created_at'))
        .values('day')
        .annotate(count=Count('id'))
        .order_by('day')
    )
    daily_data = [
        {'date': row['day'].isoformat(), 'count': row['count']}
        for row in daily
    ]

    return Response({
        'total': qs.count(),
        'by_status': {
            'pending':   status_map.get('pending', 0),
            'accepted':  status_map.get('accepted', 0),
            'en_route':  status_map.get('en_route', 0),
            'arrived':   status_map.get('arrived', 0),
            'completed': status_map.get('completed', 0),
            'cancelled': status_map.get('cancelled', 0),
        },
        'daily': daily_data,
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def export_dispatches_csv(request):
    """
    GET /api/dispatch/export/
    CSV download of dispatch history, org-scoped.

    Optional filters:
      ?status=completed
      &start_date=YYYY-MM-DD
      &end_date=YYYY-MM-DD
    """
    import csv
    import datetime
    from django.http import HttpResponse

    qs = (
        DispatchRequest.objects
        .filter(assigned_vehicle__owner__in=get_org_user_ids(request.user))
        .select_related('assigned_vehicle')
    )

    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(status=status_filter)

    start_date = request.query_params.get('start_date')
    if start_date:
        try:
            qs = qs.filter(created_at__date__gte=datetime.date.fromisoformat(start_date))
        except ValueError:
            pass

    end_date = request.query_params.get('end_date')
    if end_date:
        try:
            qs = qs.filter(created_at__date__lte=datetime.date.fromisoformat(end_date))
        except ValueError:
            pass

    qs = qs.order_by('-created_at')

    response = HttpResponse(content_type='text/csv')
    response['Content-Disposition'] = 'attachment; filename="dispatch_history.csv"'

    writer = csv.writer(response)
    writer.writerow([
        'id', 'created_at', 'request_lat', 'request_lng', 'vehicle_type',
        'assigned_vehicle', 'status', 'distance_km', 'duration_min',
        'assigned_at', 'accepted_at', 'en_route_at', 'arrived_at', 'completed_at',
    ])
    for d in qs.iterator():
        writer.writerow([
            d.id, d.created_at, d.request_lat, d.request_lng, d.vehicle_type,
            d.assigned_vehicle.name if d.assigned_vehicle else '',
            d.status, d.distance_km, d.duration_min,
            d.assigned_at, d.accepted_at, d.en_route_at, d.arrived_at, d.completed_at,
        ])

    return response


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def export_expenses_pdf(request):
    """
    GET /api/expenses/report/pdf/
    PDF download of an expense summary (fuel + maintenance), org-scoped.

    Optional filters:
      ?start_date=YYYY-MM-DD
      &end_date=YYYY-MM-DD
    """
    from django.http import HttpResponse
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
    import datetime

    org_ids = get_org_user_ids(request.user)
    owner = request.user

    fuel_logs = FuelLog.objects.filter(driver__owner__in=org_ids)
    maintenance = MaintenanceRecord.objects.filter(
        owner__in=org_ids,
        completed=True,
        cost__isnull=False,
    )

    start_date = request.query_params.get('start_date')
    end_date = request.query_params.get('end_date')
    if start_date:
        try:
            sd = datetime.date.fromisoformat(start_date)
            fuel_logs = fuel_logs.filter(created_at__date__gte=sd)
            maintenance = maintenance.filter(completed_at__date__gte=sd)
        except ValueError:
            pass
    if end_date:
        try:
            ed = datetime.date.fromisoformat(end_date)
            fuel_logs = fuel_logs.filter(created_at__date__lte=ed)
            maintenance = maintenance.filter(completed_at__date__lte=ed)
        except ValueError:
            pass

    total_fuel = float(fuel_logs.aggregate(total=Sum('amount'))['total'] or 0)
    total_maint = float(maintenance.aggregate(total=Sum('cost'))['total'] or 0)
    total_ops = total_fuel + total_maint

    response = HttpResponse(content_type='application/pdf')
    response['Content-Disposition'] = 'attachment; filename="expense_report.pdf"'

    doc = SimpleDocTemplate(
        response, pagesize=A4,
        rightMargin=15 * mm, leftMargin=15 * mm,
        topMargin=15 * mm, bottomMargin=15 * mm,
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        name='SarathiTitle', parent=styles['Title'],
        fontSize=18, textColor=colors.HexColor('#0D7377'), spaceAfter=4,
    )
    org_name = getattr(getattr(owner, 'profile', None), 'organization_name', '')

    story = []
    story.append(Paragraph('Sarathi Expense Report', title_style))
    story.append(Paragraph(f'Organization: {org_name}', styles['Normal']))
    story.append(Paragraph(f'Generated: {timezone.now().strftime("%Y-%m-%d %H:%M")} UTC', styles['Normal']))
    story.append(Spacer(1, 6 * mm))

    story.append(Paragraph('Summary', styles['Heading2']))
    summary = Table([
        ['Fuel cost (NPR)', f'{total_fuel:,.2f}'],
        ['Maintenance cost (NPR)', f'{total_maint:,.2f}'],
        ['Total operational cost (NPR)', f'{total_ops:,.2f}'],
    ], colWidths=[120 * mm, 50 * mm])
    summary.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#0D7377')),
        ('TEXTCOLOR', (0, 0), (0, -1), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('ALIGN', (1, 0), (1, -1), 'RIGHT'),
    ]))
    story.append(summary)
    story.append(Spacer(1, 8 * mm))

    fuel_by_vehicle = {
        row['vehicle__name']: float(row['fuel_total'] or 0)
        for row in fuel_logs.values('vehicle__name').annotate(fuel_total=Sum('amount'))
    }
    maint_by_vehicle = {
        row['vehicle__name']: float(row['maint_total'] or 0)
        for row in maintenance.values('vehicle__name').annotate(maint_total=Sum('cost'))
    }

    vehicle_names = sorted(set(fuel_by_vehicle) | set(maint_by_vehicle))
    if vehicle_names:
        story.append(Paragraph('Per-vehicle breakdown', styles['Heading2']))
        vehicle_rows = [['Vehicle', 'Fuel (NPR)', 'Maintenance (NPR)', 'Total (NPR)']]
        for name in vehicle_names:
            f = fuel_by_vehicle.get(name, 0)
            m = maint_by_vehicle.get(name, 0)
            vehicle_rows.append([name, f'{f:,.2f}', f'{m:,.2f}', f'{f + m:,.2f}'])
        vt = Table(vehicle_rows, colWidths=[70 * mm, 35 * mm, 35 * mm, 35 * mm])
        vt.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0D7377')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
            ('FONTSIZE', (0, 0), (-1, -1), 9),
            ('ALIGN', (1, 0), (-1, -1), 'RIGHT'),
        ]))
        story.append(vt)

    doc.build(story)
    return response


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def fuel_log_stats(request):
    """
    GET /api/fuel-logs/stats/
    Fuel spend totals for the last 30 days,
    plus a daily breakdown for charting. Owner-scoped.
    """
    from django.db.models import Sum, Count
    from django.db.models.functions import TruncDate
    import datetime

    owner = request.user
    thirty_days_ago = timezone.now() - datetime.timedelta(days=30)

    qs = FuelLog.objects.filter(
        vehicle__owner=owner,
        created_at__gte=thirty_days_ago,
    )

    total_spend = qs.aggregate(total=Sum('amount'))['total'] or 0
    total_entries = qs.count()

    daily = (
        qs.annotate(day=TruncDate('created_at'))
        .values('day')
        .annotate(total=Sum('amount'), count=Count('id'))
        .order_by('day')
    )
    daily_data = [
        {'date': row['day'].isoformat(), 'total': float(row['total'] or 0), 'count': row['count']}
        for row in daily
    ]

    return Response({
        'total_spend': float(total_spend),
        'total_entries': total_entries,
        'daily': daily_data,
    })

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def expense_summary(request):
    """
    GET /api/expenses/summary/
    Comprehensive expense tracking: fuel, maintenance, operational costs.
    Supports date range filtering via ?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
    """
    from django.db.models import Sum, Count, Avg, Q
    from django.db.models.functions import TruncDate
    import datetime
    
    owner = request.user
    
    # Date range filtering
    start_date = request.query_params.get('start_date')
    end_date = request.query_params.get('end_date')
    
    date_filters = Q(vehicle__owner=owner)
    if start_date:
        try:
            start_date = datetime.datetime.fromisoformat(start_date).date()
            date_filters &= Q(created_at__date__gte=start_date)
        except:
            pass
    
    if end_date:
        try:
            end_date = datetime.datetime.fromisoformat(end_date).date()
            date_filters &= Q(created_at__date__lte=end_date)
        except:
            pass
    
    # Fuel expenses
    fuel_logs = FuelLog.objects.filter(date_filters)
    total_fuel = fuel_logs.aggregate(total=Sum('amount'))['total'] or 0
    fuel_count = fuel_logs.count()
    
    fuel_entries = FuelEntry.objects.filter(date_filters)
    fuel_liters = fuel_entries.aggregate(total=Sum('liters'))['total'] or 0
    avg_fuel_cost_per_liter = (
        fuel_entries.aggregate(avg=Avg('cost_per_liter'))['avg'] or 0
    )
    
    # Maintenance expenses (from completed maintenance records with cost)
    maintenance = MaintenanceRecord.objects.filter(
        vehicle__owner=owner,
        completed=True
    )
    if start_date:
        maintenance = maintenance.filter(completed_at__date__gte=start_date)
    if end_date:
        maintenance = maintenance.filter(completed_at__date__lte=end_date)
    
    total_maintenance = float(maintenance.aggregate(total=Sum('cost'))['total'] or 0)
    maintenance_count = maintenance.count()
    
    total_operational = float(total_fuel) + float(total_maintenance)
    
    # By vehicle breakdown
    vehicle_fuel = (
        fuel_logs.values('vehicle__name')
        .annotate(total=Sum('amount'), count=Count('id'))
        .order_by('-total')
    )
    maint_by_vehicle = {
        row['vehicle__name']: float(row['total'] or 0)
        for row in maintenance.values('vehicle__name').annotate(total=Sum('cost'))
    }
    by_vehicle = [
        {
            'vehicle': row['vehicle__name'],
            'fuel_cost': float(row['total']),
            'maintenance_cost': maint_by_vehicle.get(row['vehicle__name'], 0),
            'count': row['count'],
        }
        for row in vehicle_fuel
    ]
    # Include vehicles that only have maintenance costs (no fuel logged)
    for name, maint_cost in maint_by_vehicle.items():
        if not any(b['vehicle'] == name for b in by_vehicle):
            by_vehicle.append({
                'vehicle': name,
                'fuel_cost': 0,
                'maintenance_cost': maint_cost,
                'count': 0,
            })
    
    # By driver breakdown
    driver_fuel = (
        fuel_logs.values('driver__name')
        .annotate(total=Sum('amount'), count=Count('id'))
        .order_by('-total')
    )
    by_driver = [
        {'driver': row['driver__name'], 'fuel_cost': float(row['total']), 'count': row['count']}
        for row in driver_fuel
    ]
    
    return Response({
        'total_fuel_cost': float(total_fuel),
        'total_maintenance_cost': float(total_maintenance),
        'total_operational_cost': total_operational,
        'fuel_entries_count': fuel_count,
        'maintenance_records_count': maintenance_count,
        'total_fuel_liters': float(fuel_liters),
        'average_fuel_cost_per_liter': float(avg_fuel_cost_per_liter),
        'by_vehicle': by_vehicle,
        'by_driver': by_driver,
        'date_range': {
            'start': start_date,
            'end': end_date,
        }
    })

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def expense_report(request):
    """
    GET /api/expenses/report/
    Detailed expense report with daily breakdown and trends.
    """
    from django.db.models import Sum, Count
    from django.db.models.functions import TruncDate
    import datetime
    
    owner = request.user
    period = request.query_params.get('period', '30')  # days
    
    try:
        days = int(period)
    except:
        days = 30
    
    start_date = timezone.now() - datetime.timedelta(days=days)
    
    # Daily fuel expenses
    fuel_daily = (
        FuelLog.objects.filter(
            vehicle__owner=owner,
            created_at__gte=start_date
        )
        .annotate(day=TruncDate('created_at'))
        .values('day')
        .annotate(fuel_cost=Sum('amount'), fuel_count=Count('id'))
        .order_by('day')
    )
    
    daily_data = [
        {
            'date': row['day'].isoformat(),
            'fuel_cost': float(row['fuel_cost'] or 0),
            'fuel_count': row['fuel_count'],
        }
        for row in fuel_daily
    ]
    
    # Monthly totals
    fuel_monthly = (
        FuelLog.objects.filter(
            vehicle__owner=owner,
            created_at__gte=start_date
        )
        .extra(select={'month': 'EXTRACT(MONTH FROM created_at)'})
        .values('month')
        .annotate(total=Sum('amount'))
        .order_by('month')
    )
    
    monthly_data = [
        {'month': int(row['month']), 'total': float(row['total'] or 0)}
        for row in fuel_monthly
    ]
    
    return Response({
        'period_days': days,
        'daily_breakdown': daily_data,
        'monthly_summary': monthly_data,
    })

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def vehicle_expense_detail(request, vehicle_id):
    """
    GET /api/vehicles/{vehicle_id}/expenses/
    Expense breakdown for a specific vehicle.
    """
    from django.db.models import Sum, Count, Avg
    
    owner = request.user
    try:
        vehicle = Vehicle.objects.get(id=vehicle_id, owner=owner)
    except Vehicle.DoesNotExist:
        return Response({'error': 'Vehicle not found'}, status=404)
    
    # Fuel logs
    fuel_logs = FuelLog.objects.filter(vehicle=vehicle)
    total_fuel = fuel_logs.aggregate(total=Sum('amount'))['total'] or 0
    fuel_count = fuel_logs.count()
    avg_per_transaction = (
        fuel_logs.aggregate(avg=Avg('amount'))['avg'] or 0
    )
    
    # Fuel entries
    fuel_entries = FuelEntry.objects.filter(vehicle=vehicle)
    total_liters = fuel_entries.aggregate(total=Sum('liters'))['total'] or 0
    
    # Maintenance
    maintenance = MaintenanceRecord.objects.filter(vehicle=vehicle, completed=True)
    maintenance_count = maintenance.count()
    
    # Recent transactions
    recent_fuel = FuelLog.objects.filter(vehicle=vehicle).order_by('-created_at')[:5]
    fuel_data = FuelLogSerializer(recent_fuel, many=True).data
    
    return Response({
        'vehicle_id': vehicle.id,
        'vehicle_name': vehicle.name,
        'total_fuel_cost': float(total_fuel),
        'total_fuel_liters': float(total_liters),
        'fuel_transactions': fuel_count,
        'average_per_transaction': float(avg_per_transaction),
        'maintenance_completed': maintenance_count,
        'recent_transactions': fuel_data,
    })

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def driver_expense_detail(request, driver_id):
    """
    GET /api/drivers/{driver_id}/expenses/
    Expense breakdown for a specific driver.
    """
    from django.db.models import Sum, Count, Avg
    
    owner = request.user
    try:
        driver = Driver.objects.get(id=driver_id, user__profile__organization=owner)
    except Driver.DoesNotExist:
        return Response({'error': 'Driver not found'}, status=404)
    
    # Fuel logs
    fuel_logs = FuelLog.objects.filter(driver=driver)
    total_fuel = fuel_logs.aggregate(total=Sum('amount'))['total'] or 0
    fuel_count = fuel_logs.count()
    avg_per_transaction = (
        fuel_logs.aggregate(avg=Avg('amount'))['avg'] or 0
    )
    
    # Fuel entries
    fuel_entries = FuelEntry.objects.filter(driver=driver)
    total_liters = fuel_entries.aggregate(total=Sum('liters'))['total'] or 0
    
    # Recent transactions
    recent_fuel = FuelLog.objects.filter(driver=driver).order_by('-created_at')[:5]
    fuel_data = FuelLogSerializer(recent_fuel, many=True).data
    
    return Response({
        'driver_id': driver.id,
        'driver_name': driver.name,
        'total_fuel_cost': float(total_fuel),
        'total_fuel_liters': float(total_liters),
        'fuel_transactions': fuel_count,
        'average_per_transaction': float(avg_per_transaction),
        'recent_transactions': fuel_data,
    })

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def fuel_prices(request):
    """
    GET /api/fuel-prices/
    Returns current fuel prices from NOC for auto-calculation in forms.
    """
    prices = FuelPrice.objects.all()
    serializer = FuelPriceSerializer(prices, many=True)
    return Response(serializer.data)


# ---------------------------------------------------------------------------
# Analytics Dashboard API
# ---------------------------------------------------------------------------

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def analytics_dashboard(request):
    """
    GET /api/analytics/dashboard/
    Returns aggregated data for admin dashboard charts and KPIs.
    Org-scoped: returns data for the current user's organization.
    """
    from datetime import timedelta
    from django.db.models import Count, Q, Sum, Avg, F, Value, CharField
    from django.db.models.functions import TruncDate, Coalesce
    
    user = request.user
    org_ids = get_org_user_ids(user)
    
    # Base querysets scoped to organization
    vehicles = Vehicle.objects.filter(owner__in=org_ids)
    drivers = Driver.objects.filter(owner__in=org_ids)
    dispatches = DispatchRequest.objects.filter(assigned_vehicle__owner__in=org_ids)
    emergencies = EmergencyRequest.objects.filter(user__in=org_ids)
    issues = IssueReport.objects.filter(driver__owner__in=org_ids)
    fuel_entries = FuelEntry.objects.filter(driver__owner__in=org_ids)
    
    # ── 1. Fleet Status Pie Data ──────────────────────────────────────────
    total_vehicles = vehicles.count()
    available_count = vehicles.filter(is_available=True, admin_blocked=False).count()
    unavailable_count = vehicles.filter(is_available=False).count()
    blocked_count = vehicles.filter(admin_blocked=True).count()
    
    fleet_status = [
        { 'name': 'Available', 'value': available_count, 'color': '#10b981' },
        { 'name': 'Unavailable', 'value': unavailable_count, 'color': '#f59e0b' },
        { 'name': 'Blocked', 'value': blocked_count, 'color': '#ef4444' },
    ]
    
    # ── 2. Dispatch Volume by Day (last 7 days) ──────────────────────────
    today = timezone.now().date()
    seven_days_ago = today - timedelta(days=6)
    
    daily_dispatches = (
        dispatches
        .filter(created_at__date__gte=seven_days_ago)
        .annotate(date=TruncDate('created_at'))
        .values('date')
        .annotate(count=Count('id'))
        .order_by('date')
    )
    
    # Fill in missing days with 0
    dispatch_by_day = {}
    for i in range(7):
        d = seven_days_ago + timedelta(days=i)
        dispatch_by_day[d.strftime('%a %d')] = 0
    
    for d in daily_dispatches:
        key = d['date'].strftime('%a %d')
        dispatch_by_day[key] = d['count']
    
    dispatch_volume = [
        { 'day': k, 'count': v } for k, v in dispatch_by_day.items()
    ]
    
    # ── 3. Emergency Trends (last 7 days) ────────────────────────────────
    daily_emergencies = (
        emergencies
        .filter(created_at__date__gte=seven_days_ago)
        .annotate(date=TruncDate('created_at'))
        .values('date')
        .annotate(count=Count('id'))
        .order_by('date')
    )
    
    emergency_by_day = {}
    for i in range(7):
        d = seven_days_ago + timedelta(days=i)
        emergency_by_day[d.strftime('%a %d')] = 0
    
    for e in daily_emergencies:
        key = e['date'].strftime('%a %d')
        emergency_by_day[key] = e['count']
    
    emergency_trends = [
        { 'day': k, 'count': v } for k, v in emergency_by_day.items()
    ]
    
    # ── 4. Vehicle Type Distribution ─────────────────────────────────────
    vehicle_types = (
        vehicles
        .values('vehicle_type')
        .annotate(count=Count('id'))
        .order_by('-count')
    )
    
    type_colors = {
        'ambulance': '#dc2626',
        'logistics': '#2563eb',
        'municipal': '#059669',
    }
    
    vehicle_type_dist = [
        {
            'name': v['vehicle_type'].title(),
            'value': v['count'],
            'color': type_colors.get(v['vehicle_type'], '#6b7280'),
        }
        for v in vehicle_types
    ]
    
    # ── 5. Top Drivers by Completed Dispatches ───────────────────────────
    top_drivers = (
        drivers
        .annotate(
            completed_dispatches=Count(
                'assigned_vehicles__dispatch_requests',
                filter=Q(assigned_vehicles__dispatch_requests__status='completed')
            )
        )
        .filter(completed_dispatches__gt=0)
        .order_by('-completed_dispatches')[:5]
    )
    
    top_drivers_data = [
        {
            'name': d.name,
            'completed': d.completed_dispatches,
        }
        for d in top_drivers
    ]
    
    # ── 6. Issue Status Breakdown ────────────────────────────────────────
    issue_breakdown = (
        issues
        .values('status')
        .annotate(count=Count('id'))
        .order_by('status')
    )
    
    issue_colors = {
        'open': '#ef4444',
        'acknowledged': '#f59e0b',
        'resolved': '#10b981',
    }
    
    issue_data = [
        {
            'name': i['status'].title(),
            'value': i['count'],
            'color': issue_colors.get(i['status'], '#6b7280'),
        }
        for i in issue_breakdown
    ]
    
    # ── 7. Fuel Cost Trends (last 7 days) ────────────────────────────────
    daily_fuel_cost = (
        fuel_entries
        .filter(fueled_at__date__gte=seven_days_ago)
        .annotate(date=TruncDate('fueled_at'))
        .values('date')
        .annotate(
            total_cost=Sum('total_cost'),
            total_liters=Sum('liters'),
        )
        .order_by('date')
    )
    
    fuel_by_day = {}
    for i in range(7):
        d = seven_days_ago + timedelta(days=i)
        fuel_by_day[d.strftime('%a %d')] = { 'cost': 0, 'liters': 0 }
    
    for f in daily_fuel_cost:
        key = f['date'].strftime('%a %d')
        fuel_by_day[key] = {
            'cost': float(f['total_cost'] or 0),
            'liters': float(f['total_liters'] or 0),
        }
    
    fuel_trends = [
        { 'day': k, 'cost': v['cost'], 'liters': v['liters'] }
        for k, v in fuel_by_day.items()
    ]
    
    # ── 8. KPI Summary Cards ─────────────────────────────────────────────
    avg_response_time = None
    response_times = dispatches.filter(
        assigned_at__isnull=False,
        arrived_at__isnull=False
    ).annotate(
        rt=ExpressionWrapper(
            F('arrived_at') - F('assigned_at'),
            output_field=DurationField()
        )
    ).values_list('rt', flat=True)
    
    if response_times:
        avg_seconds = sum(rt.total_seconds() for rt in response_times) / len(response_times)
        avg_response_time = round(avg_seconds / 60, 1)  # in minutes

    # ── 9. Fuel Efficiency (km/L per vehicle) ────────────────────────────
    fuel_logs = FuelLog.objects.filter(driver__owner__in=org_ids)
    vehicle_distances = {v.id: v.total_distance_km for v in vehicles.all()}
    vehicle_eff_rows = (
        fuel_logs.values('vehicle__id')
        .annotate(total_liters=Sum('liters'))
        .order_by('vehicle__id')
    )
    vehicle_efficiency = []
    for row in vehicle_eff_rows:
        total_liters = float(row['total_liters'] or 0)
        distance_km = vehicle_distances.get(row['vehicle__id'], 0)
        if total_liters <= 0 or distance_km <= 0:
            continue
        vehicle_efficiency.append({
            'vehicle_id': row['vehicle__id'],
            'distance_km': round(distance_km, 1),
            'liters': round(total_liters, 2),
            'km_per_liter': round(distance_km / total_liters, 2),
        })
    vehicle_efficiency.sort(key=lambda x: x['km_per_liter'], reverse=True)

    # ── 10. Driver Performance (acceptance rate + completion) ────────────
    driver_perf_rows = (
        drivers
        .annotate(
            total_trips=Count('assigned_vehicles__dispatch_requests', distinct=True),
            accepted_trips=Count(
                'assigned_vehicles__dispatch_requests',
                filter=Q(assigned_vehicles__dispatch_requests__status__in=ACCEPTED_DISPATCH_STATUSES),
                distinct=True,
            ),
            completed_trips=Count(
                'assigned_vehicles__dispatch_requests',
                filter=Q(assigned_vehicles__dispatch_requests__status='completed'),
                distinct=True,
            ),
        )
        .filter(total_trips__gt=0)
        .order_by('-completed_trips')[:5]
    )

    # Harsh-driving events per driver (rolling window) — folded into the
    # driver safety score shown in the performance table.
    event_cutoff = timezone.now() - timezone.timedelta(days=DRIVER_SCORE_WINDOW_DAYS)
    driver_ids = [d.id for d in driver_perf_rows]
    event_breakdown = {}
    if driver_ids:
        agg = (
            DrivingEvent.objects
            .filter(driver_id__in=driver_ids, created_at__gte=event_cutoff)
            .values('driver_id', 'event_type')
            .annotate(count=Count('id'))
        )
        for row in agg:
            entry = event_breakdown.setdefault(
                row['driver_id'], {'harsh_accel': 0, 'harsh_brake': 0, 'harsh_turn': 0, 'total': 0}
            )
            entry[row['event_type']] = row['count']
            entry['total'] += row['count']

    driver_performance = []
    for d in driver_perf_rows:
        breakdown = event_breakdown.get(d.id, {'harsh_accel': 0, 'harsh_brake': 0, 'harsh_turn': 0, 'total': 0})
        penalty = sum(breakdown[row_type] * w for row_type, w in DRIVER_SCORE_WEIGHTS.items())
        driver_performance.append({
            'name': d.name,
            'total_trips': d.total_trips,
            'accepted_trips': d.accepted_trips,
            'acceptance_rate': round((d.accepted_trips / d.total_trips) * 100, 1) if d.total_trips else 0,
            'completed_trips': d.completed_trips,
            'score': max(0, 100 - penalty),
            'harsh_events': breakdown['total'],
            'events': breakdown,
        })

    return Response({
        'fleet_status': fleet_status,
        'dispatch_volume': dispatch_volume,
        'emergency_trends': emergency_trends,
        'vehicle_type_dist': vehicle_type_dist,
        'top_drivers': top_drivers_data,
        'issue_breakdown': issue_data,
        'fuel_trends': fuel_trends,
        'vehicle_efficiency': vehicle_efficiency,
        'driver_performance': driver_performance,
        'kpi': {
            'total_vehicles': total_vehicles,
            'available': available_count,
            'total_drivers': drivers.count(),
            'active_drivers': drivers.filter(is_on_duty=True).count(),
            'total_dispatches': dispatches.count(),
            'completed_dispatches': dispatches.filter(status='completed').count(),
            'pending_emergencies': emergencies.filter(status='pending').count(),
            'open_issues': issues.filter(status='open').count(),
            'avg_response_time_min': avg_response_time,
            'total_fuel_cost': float(fuel_entries.aggregate(total=Sum('total_cost'))['total'] or 0),
        }
    })

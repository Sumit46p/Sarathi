from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance
from django.db.models import Q
from django.utils import timezone
from .osrm import get_route_distance
import threading

from .models import Vehicle, DispatchRequest, Driver, MaintenanceRecord, IssueReport
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
)


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
    Body: {"username": "...", "license_number": "...", "new_password": "..."}
    Allows resetting password if username and license match.
    """
    username = request.data.get('username')
    license_number = request.data.get('license_number')
    new_password = request.data.get('new_password')

    if not all([username, license_number, new_password]):
        return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)
    
    if len(new_password) < 6:
        return Response({'error': 'Password must be at least 6 characters'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        from django.contrib.auth.models import User
        user = User.objects.get(username=username)
        driver = Driver.objects.get(user=user, license_number=license_number)
    except (User.DoesNotExist, Driver.DoesNotExist):
        return Response({'error': 'Invalid username or license number'}, status=status.HTTP_400_BAD_REQUEST)

    user.set_password(new_password)
    user.save()

    driver.requires_password_change = False
    driver.save(update_fields=['requires_password_change'])

    return Response({'success': True})


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

    vehicle.location = Point(
        serializer.validated_data['lng'],
        serializer.validated_data['lat'],
        srid=4326,
    )
    vehicle.last_location_at = timezone.now()
    vehicle.save(update_fields=['location', 'last_location_at'])

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

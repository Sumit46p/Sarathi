from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from django.contrib.gis.geos import Point
from django.utils import timezone
from django.db import transaction
from django.db.models import Q
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from .models import (
    DispatchRequest,
    Vehicle,
    Notification,
    OperationalLocation,
    EmergencyRequest,
    Driver,
)
from .serializers import (
    DispatchRequestSerializer,
    OperationalLocationSerializer,
    EmergencyRequestSerializer,
)
from .dispatch_engine import DispatchEngine
from .views import get_org_user_ids, ACTIVE_DISPATCH_STATUSES


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def operational_locations(request):
    """
    GET /api/operational-locations/?q=<query>&category=<category>
    Searches application database for operational landmarks (depots, warehouses, bus parks, landmarks, etc.)
    """
    qs = OperationalLocation.objects.filter(is_active=True)

    query = request.query_params.get('q', '').strip()
    category = request.query_params.get('category', '').strip()

    if query:
        qs = qs.filter(
            Q(name__icontains=query) |
            Q(address__icontains=query) |
            Q(category__icontains=query)
        )

    if category:
        qs = qs.filter(category__iexact=category)

    results = qs.order_by('name')[:30]
    serializer = OperationalLocationSerializer(results, many=True)
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def dispatch_preview(request):
    """
    POST /api/dispatch/preview/
    Evaluates rule-based candidate ranking using real road OSRM ETA.
    Supports Normal Logistics (Pickup) and Breakdown Recovery (Breakdown site).
    Body:
    {
        "lat": 26.6528,
        "lng": 87.9942,
        "vehicle_type": "logistics",
        "operation_type": "NORMAL_LOGISTICS" | "EMERGENCY_REPLACEMENT",
        "failed_vehicle_id": 12 (optional: excluded from candidates)
    }
    """
    data = request.data
    lat = data.get('lat')
    lng = data.get('lng')
    vehicle_type = data.get('vehicle_type')

    if lat is None or lng is None:
        return Response({'error': 'Latitude and longitude are required.'}, status=status.HTTP_400_BAD_REQUEST)

    if not vehicle_type:
        return Response({'error': 'Vehicle type is required.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        lat = float(lat)
        lng = float(lng)
    except (TypeError, ValueError):
        return Response({'error': 'Invalid coordinates provided.'}, status=status.HTTP_400_BAD_REQUEST)

    op_type = data.get('operation_type', 'NORMAL_LOGISTICS')
    is_emergency = (op_type == 'EMERGENCY_REPLACEMENT')
    request_type = 'EMERGENCY' if is_emergency else 'NORMAL'
    priority = 'HIGH' if is_emergency else 'MEDIUM'

    org = None
    if hasattr(request.user, 'profile') and request.user.profile.organization:
        org = request.user.profile.organization

    engine = DispatchEngine(
        target_lat=lat,
        target_lng=lng,
        vehicle_type=vehicle_type,
        request_type=request_type,
        priority=priority,
        organization=org,
        http_request=request
    )

    recommended, candidates, diagnostics = engine.evaluate()

    # If this is breakdown recovery, filter out the failed vehicle itself if present
    failed_id = data.get('failed_vehicle_id')
    if failed_id:
        try:
            failed_id = int(failed_id)
            if recommended and recommended.vehicle.id == failed_id:
                recommended = candidates[0] if candidates else None
                candidates = candidates[1:] if candidates else []
            candidates = [c for c in candidates if c.vehicle.id != failed_id]
        except (ValueError, TypeError):
            pass

    return Response({
        'recommended': recommended.to_dict() if recommended else None,
        'candidates': [c.to_dict() for c in candidates],
        'diagnostics': diagnostics,
        'summary': {
            'target_lat': lat,
            'target_lng': lng,
            'vehicle_type': vehicle_type,
            'operation_type': op_type,
            'total_evaluated': (1 if recommended else 0) + len(candidates),
        }
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def dispatch_confirm(request):
    """
    POST /api/dispatch/confirm/
    Creates a new Normal Logistics Delivery Operation.
    Automatically assigns the vehicle's already-assigned driver!
    """
    data = request.data
    vehicle_id = data.get('vehicle_id')
    pickup_lat = data.get('pickup_lat') or data.get('lat')
    pickup_lng = data.get('pickup_lng') or data.get('lng')

    if not vehicle_id:
        return Response({'error': 'vehicle_id is required.'}, status=status.HTTP_400_BAD_REQUEST)
    if pickup_lat is None or pickup_lng is None:
        return Response({'error': 'Pickup latitude and longitude are required.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        pickup_lat = float(pickup_lat)
        pickup_lng = float(pickup_lng)
    except (TypeError, ValueError):
        return Response({'error': 'Invalid pickup coordinates.'}, status=status.HTTP_400_BAD_REQUEST)

    dest_lat = data.get('dest_lat')
    dest_lng = data.get('dest_lng')
    if dest_lat is not None and dest_lng is not None:
        try:
            dest_lat = float(dest_lat)
            dest_lng = float(dest_lng)
        except (TypeError, ValueError):
            dest_lat, dest_lng = None, None

    try:
        vehicle = Vehicle.objects.select_related('driver', 'driver__user', 'organization').get(pk=vehicle_id)
    except Vehicle.DoesNotExist:
        return Response({'error': 'Vehicle not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not vehicle.driver:
        return Response({
            'error': f'Vehicle {vehicle.name} has no driver assigned in Fleet Management.'
        }, status=status.HTTP_400_BAD_REQUEST)

    if not vehicle.is_available or vehicle.has_active_dispatch:
        return Response({
            'error': f'Vehicle {vehicle.name} ({vehicle.number_plate}) is not currently available.'
        }, status=status.HTTP_409_CONFLICT)

    pickup_name = data.get('pickup_name') or data.get('location_name') or 'Pickup Site'
    pickup_address = data.get('pickup_address') or data.get('address') or f'{pickup_lat:.5f}, {pickup_lng:.5f}'
    destination_name = data.get('destination_name') or 'Delivery Destination'
    destination_address = data.get('destination_address') or (f'{dest_lat:.5f}, {dest_lng:.5f}' if dest_lat else 'Destination Depot')
    cargo_description = data.get('cargo_description') or 'General Freight'
    cargo_weight_kg = data.get('cargo_weight_kg')
    selection_reason = data.get('selection_reason') or 'Rule-based fleet assignment by ETA.'
    distance_km = data.get('distance_km')
    eta_min = data.get('eta_min') or data.get('duration_min')

    try:
        with transaction.atomic():
            # 1. Update vehicle status to assigned/in_use
            vehicle.is_available = False
            vehicle.vehicle_status = 'assigned'
            vehicle.save(update_fields=['is_available', 'vehicle_status'])

            # 2. Create DispatchRequest record
            pickup_pt = Point(pickup_lng, pickup_lat, srid=4326)
            dest_pt = Point(dest_lng, dest_lat, srid=4326) if (dest_lat and dest_lng) else None

            dispatch = DispatchRequest.objects.create(
                operation_type='NORMAL_LOGISTICS',
                request_type='NORMAL',
                priority='MEDIUM',
                request_lat=pickup_lat,
                request_lng=pickup_lng,
                pickup_location=pickup_pt,
                location_name=pickup_name,
                address=pickup_address,
                dest_lat=dest_lat,
                dest_lng=dest_lng,
                destination=dest_pt,
                destination_name=destination_name,
                destination_address=destination_address,
                cargo_description=cargo_description,
                cargo_weight_kg=float(cargo_weight_kg) if cargo_weight_kg else None,
                vehicle_type=vehicle.vehicle_type,
                assigned_vehicle=vehicle,
                status='assigned',
                assigned_at=timezone.now(),
                distance_km=float(distance_km) if distance_km is not None else None,
                duration_min=float(eta_min) if eta_min is not None else None,
                selection_reason=selection_reason,
                created_by=request.user,
                organization=vehicle.organization,
                used_osrm=True,
            )

            # 3. Create Driver Notification
            if vehicle.driver and vehicle.driver.user:
                Notification.objects.create(
                    user=vehicle.driver.user,
                    notification_type='trip',
                    title=f'📦 New Delivery: {pickup_name} → {destination_name}',
                    message=f'Vehicle {vehicle.name} assigned logistics delivery of {cargo_description}. Pickup: {pickup_name}.',
                    related_dispatch=dispatch,
                )

        serializer = DispatchRequestSerializer(dispatch, context={'request': request})
        return Response({
            'success': True,
            'message': f'Operation #{dispatch.id} dispatched to {vehicle.name} (Driver: {vehicle.driver.name}).',
            'dispatch': serializer.data,
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response({'error': f'Failed to create dispatch: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def driver_report_breakdown(request):
    """
    POST /api/dispatch/driver-breakdown/
    Driver (or Admin) reports that an active delivery vehicle broke down mid-journey.
    Body:
    {
        "dispatch_id": 15,
        "breakdown_reason": "Engine Overheating",
        "description": "Vehicle stopped on highway, parts needed",
        "lat": 26.65,
        "lng": 87.99
    }
    """
    data = request.data
    dispatch_id = data.get('dispatch_id')
    breakdown_reason = data.get('breakdown_reason') or 'Engine / Mechanical Failure'
    description = data.get('description') or breakdown_reason

    try:
        dispatch = DispatchRequest.objects.select_related('assigned_vehicle', 'assigned_vehicle__driver').get(pk=dispatch_id)
    except DispatchRequest.DoesNotExist:
        return Response({'error': 'Active dispatch operation not found.'}, status=status.HTTP_404_NOT_FOUND)

    failed_vehicle = dispatch.assigned_vehicle
    if not failed_vehicle:
        return Response({'error': 'Dispatch has no assigned vehicle.'}, status=status.HTTP_400_BAD_REQUEST)

    # Coordinates of breakdown
    lat = data.get('lat')
    lng = data.get('lng')
    if lat is not None and lng is not None:
        try:
            lat = float(lat)
            lng = float(lng)
        except (TypeError, ValueError):
            lat = failed_vehicle.location.y if failed_vehicle.location else 27.7
            lng = failed_vehicle.location.x if failed_vehicle.location else 85.3
    else:
        lat = failed_vehicle.location.y if failed_vehicle.location else 27.7
        lng = failed_vehicle.location.x if failed_vehicle.location else 85.3

    breakdown_pt = Point(lng, lat, srid=4326)

    try:
        with transaction.atomic():
            # 1. Update vehicle status to maintenance and unavailable
            failed_vehicle.is_available = False
            failed_vehicle.admin_blocked = True
            failed_vehicle.vehicle_status = 'maintenance'
            failed_vehicle.save(update_fields=['is_available', 'admin_blocked', 'vehicle_status'])

            # 2. Update dispatch status to VEHICLE_BREAKDOWN
            dispatch.status = 'VEHICLE_BREAKDOWN'
            dispatch.breakdown_reason = breakdown_reason
            dispatch.failed_vehicle = failed_vehicle
            dispatch.save(update_fields=['status', 'breakdown_reason', 'failed_vehicle'])

            # 3. Create EmergencyRequest record
            driver_user = request.user
            if failed_vehicle.driver and failed_vehicle.driver.user:
                driver_user = failed_vehicle.driver.user

            emergency = EmergencyRequest.objects.create(
                user=driver_user,
                emergency_type='breakdown',
                description=f"BREAKDOWN: {failed_vehicle.name} ({failed_vehicle.number_plate}) - {breakdown_reason}. Delivery: {dispatch.location_name} → {dispatch.destination_name}. Cargo: {dispatch.cargo_description}.",
                location=breakdown_pt,
                assigned_vehicle=failed_vehicle,
                related_dispatch=dispatch,
                status='pending',
            )

        serializer = EmergencyRequestSerializer(emergency, context={'request': request})
        return Response({
            'success': True,
            'message': f'Breakdown reported for {failed_vehicle.name}. Emergency recovery requested.',
            'emergency': serializer.data,
            'dispatch': DispatchRequestSerializer(dispatch, context={'request': request}).data,
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response({'error': f'Failed to record breakdown: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def breakdown_requests_list(request):
    """
    GET /api/dispatch/breakdown-requests/
    Returns all pending/active breakdown recovery requests for admin review.
    """
    qs = EmergencyRequest.objects.select_related(
        'assigned_vehicle',
        'related_dispatch',
        'replacement_dispatch'
    ).filter(emergency_type='breakdown').order_by('-created_at')

    serializer = EmergencyRequestSerializer(qs, many=True, context={'request': request})
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def approve_breakdown_recovery(request):
    """
    POST /api/dispatch/approve-recovery/
    Admin approves recovery and dispatches a replacement vehicle.
    Body:
    {
        "emergency_id": 5,
        "replacement_vehicle_id": 18,
        "recovery_lat": 26.65,
        "recovery_lng": 87.99,
        "selection_reason": "Fastest available replacement truck to breakdown site."
    }
    """
    data = request.data
    emergency_id = data.get('emergency_id')
    replacement_vehicle_id = data.get('replacement_vehicle_id')

    if not emergency_id:
        return Response({'error': 'emergency_id is required.'}, status=status.HTTP_400_BAD_REQUEST)
    if not replacement_vehicle_id:
        return Response({'error': 'replacement_vehicle_id is required.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        emergency = EmergencyRequest.objects.select_related(
            'related_dispatch', 'assigned_vehicle'
        ).get(pk=emergency_id)
    except EmergencyRequest.DoesNotExist:
        return Response({'error': 'Emergency breakdown request not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
        replacement_vehicle = Vehicle.objects.select_related('driver', 'driver__user', 'organization').get(pk=replacement_vehicle_id)
    except Vehicle.DoesNotExist:
        return Response({'error': 'Replacement vehicle not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not replacement_vehicle.driver:
        return Response({
            'error': f'Replacement vehicle {replacement_vehicle.name} has no driver assigned.'
        }, status=status.HTTP_400_BAD_REQUEST)

    if not replacement_vehicle.is_available:
        return Response({
            'error': f'Replacement vehicle {replacement_vehicle.name} is not available.'
        }, status=status.HTTP_409_CONFLICT)

    original_dispatch = emergency.related_dispatch
    failed_vehicle = emergency.assigned_vehicle

    rec_lat = data.get('recovery_lat') or (emergency.location.y if emergency.location else None)
    rec_lng = data.get('recovery_lng') or (emergency.location.x if emergency.location else None)
    if rec_lat is None or rec_lng is None:
        rec_lat = failed_vehicle.location.y if (failed_vehicle and failed_vehicle.location) else 27.7
        rec_lng = failed_vehicle.location.x if (failed_vehicle and failed_vehicle.location) else 85.3

    recovery_point = Point(rec_lng, rec_lat, srid=4326)
    reason = data.get('selection_reason') or f"Breakdown recovery replacement for {failed_vehicle.name if failed_vehicle else 'failed vehicle'}."

    try:
        with transaction.atomic():
            # 1. Update replacement vehicle status
            replacement_vehicle.is_available = False
            replacement_vehicle.vehicle_status = 'assigned'
            replacement_vehicle.save(update_fields=['is_available', 'vehicle_status'])

            # 2. Update original dispatch status to RECOVERY_IN_PROGRESS
            if original_dispatch:
                original_dispatch.status = 'RECOVERY_IN_PROGRESS'
                original_dispatch.save(update_fields=['status'])

            # 3. Create Emergency Recovery Operation
            # Inherits original destination and cargo info!
            dest_pt = original_dispatch.destination if original_dispatch else None
            dest_lat = original_dispatch.dest_lat if original_dispatch else None
            dest_lng = original_dispatch.dest_lng if original_dispatch else None
            dest_name = original_dispatch.destination_name if original_dispatch else 'Original Destination'
            dest_addr = original_dispatch.destination_address if original_dispatch else ''
            cargo_desc = original_dispatch.cargo_description if original_dispatch else 'Transferred Cargo'
            cargo_wt = original_dispatch.cargo_weight_kg if original_dispatch else None

            recovery_op = DispatchRequest.objects.create(
                operation_type='EMERGENCY_REPLACEMENT',
                request_type='EMERGENCY',
                priority='CRITICAL',
                original_dispatch=original_dispatch,
                failed_vehicle=failed_vehicle,
                breakdown_reason=emergency.description,
                request_lat=rec_lat,
                request_lng=rec_lng,
                pickup_location=recovery_point,
                location_name=f"Breakdown Site ({failed_vehicle.name if failed_vehicle else 'Unit'})",
                address=f"Transfer goods from {failed_vehicle.name if failed_vehicle else 'failed unit'} at GPS {rec_lat:.5f}, {rec_lng:.5f}",
                dest_lat=dest_lat,
                dest_lng=dest_lng,
                destination=dest_pt,
                destination_name=dest_name,
                destination_address=dest_addr,
                cargo_description=cargo_desc,
                cargo_weight_kg=cargo_wt,
                vehicle_type=replacement_vehicle.vehicle_type,
                assigned_vehicle=replacement_vehicle,
                status='assigned',
                assigned_at=timezone.now(),
                selection_reason=reason,
                created_by=request.user,
                organization=replacement_vehicle.organization,
                used_osrm=True,
            )

            # 4. Update emergency request
            emergency.status = 'dispatched'
            emergency.replacement_dispatch = recovery_op
            emergency.save(update_fields=['status', 'replacement_dispatch'])

            # 5. Notify replacement vehicle driver
            if replacement_vehicle.driver and replacement_vehicle.driver.user:
                Notification.objects.create(
                    user=replacement_vehicle.driver.user,
                    notification_type='trip',
                    title=f'🚨 Emergency Recovery: Transfer goods from {failed_vehicle.name if failed_vehicle else "broken down unit"}',
                    message=f'Head immediately to breakdown location ({rec_lat:.4f}, {rec_lng:.4f}) to receive cargo and deliver to {dest_name}.',
                    related_dispatch=recovery_op,
                )

        return Response({
            'success': True,
            'message': f'Emergency recovery approved. Replacement unit {replacement_vehicle.name} dispatched.',
            'recovery_dispatch': DispatchRequestSerializer(recovery_op, context={'request': request}).data,
            'emergency': EmergencyRequestSerializer(emergency, context={'request': request}).data,
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response({'error': f'Failed to approve recovery: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def dispatch_active_list(request):
    """
    GET /api/dispatch/active/
    Returns all active operations (Normal Deliveries and Recovery Operations).
    """
    active_statuses = [
        'assigned', 'dispatched', 'DISPATCHED', 'accepted', 'en_route', 'arrived',
        'in_service', 'RESPONDING', 'IN_PROGRESS',
        'EN_ROUTE_TO_PICKUP', 'AT_PICKUP', 'IN_TRANSIT',
        'VEHICLE_BREAKDOWN', 'RECOVERY_IN_PROGRESS',
        'EN_ROUTE_TO_BREAKDOWN', 'AT_BREAKDOWN_LOCATION',
        'GOODS_TRANSFERRED', 'IN_TRANSIT_TO_DESTINATION',
    ]

    qs = DispatchRequest.objects.select_related(
        'assigned_vehicle',
        'assigned_vehicle__driver',
        'assigned_vehicle__driver__user',
        'failed_vehicle',
        'original_dispatch'
    ).filter(
        status__in=active_statuses
    ).order_by('-created_at')

    serializer = DispatchRequestSerializer(qs, many=True, context={'request': request})
    return Response(serializer.data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def dispatch_request_transition(request, pk):
    """
    POST /api/dispatch/<pk>/transition/
    Advances or completes an operation.
    When a replacement recovery operation completes, also marks original operation completed!
    """
    try:
        dispatch = DispatchRequest.objects.select_related(
            'assigned_vehicle',
            'assigned_vehicle__driver',
            'original_dispatch',
            'failed_vehicle'
        ).get(pk=pk)
    except DispatchRequest.DoesNotExist:
        return Response({'error': 'Dispatch operation not found.'}, status=status.HTTP_404_NOT_FOUND)

    new_status = request.data.get('status')
    if not new_status:
        return Response({'error': 'New status is required.'}, status=status.HTTP_400_BAD_REQUEST)

    # Valid transitions lookup
    valid_transitions = DispatchRequest.VALID_TRANSITIONS.get(dispatch.status, [])
    matched_target = None
    for target in valid_transitions:
        if target.lower() == new_status.lower():
            matched_target = target
            break

    # Admin override transitions
    if not matched_target:
        allowed_admin = [
            'accepted', 'en_route', 'arrived', 'in_service', 'completed', 'cancelled', 'rejected',
            'EN_ROUTE_TO_PICKUP', 'AT_PICKUP', 'IN_TRANSIT', 'ARRIVED_AT_DESTINATION',
            'VEHICLE_BREAKDOWN', 'RECOVERY_IN_PROGRESS',
            'EN_ROUTE_TO_BREAKDOWN', 'AT_BREAKDOWN_LOCATION', 'GOODS_TRANSFERRED', 'IN_TRANSIT_TO_DESTINATION',
        ]
        for target in allowed_admin:
            if target.lower() == new_status.lower():
                matched_target = target
                break

    if not matched_target:
        return Response({
            'error': f"Cannot transition operation from '{dispatch.status}' to '{new_status}'."
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        dispatch.transition_to(matched_target)
    except ValueError as e:
        return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)

    # When operation completes or is cancelled
    if matched_target in ['completed', 'cancelled', 'rejected', 'expired']:
        if dispatch.assigned_vehicle:
            dispatch.assigned_vehicle.is_available = True
            dispatch.assigned_vehicle.vehicle_status = 'available'
            dispatch.assigned_vehicle.save(update_fields=['is_available', 'vehicle_status'])
            dispatch.assigned_vehicle.recompute_availability()

        # If this was a replacement operation that completed, complete the original operation too!
        if matched_target == 'completed' and dispatch.original_dispatch:
            orig = dispatch.original_dispatch
            orig.status = 'completed'
            orig.completed_at = timezone.now()
            orig.save(update_fields=['status', 'completed_at'])

    serializer = DispatchRequestSerializer(dispatch, context={'request': request})
    return Response(serializer.data)

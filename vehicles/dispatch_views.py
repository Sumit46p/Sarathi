from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from django.contrib.gis.geos import Point
from django.utils import timezone

from .models import DispatchRequest, Vehicle, Notification
from .serializers import DispatchRequestSerializer
from .dispatch_engine import DispatchEngine
from .views import get_org_user_ids

class DispatchRequestListCreateView(generics.ListCreateAPIView):
    serializer_class = DispatchRequestSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        qs = DispatchRequest.objects.all()
        # Admin / Staff filtering if organization is implemented
        if hasattr(user, 'profile') and user.profile.organization:
            qs = qs.filter(organization=user.profile.organization)
        return qs.order_by('-created_at')

    def perform_create(self, serializer):
        user = self.request.user
        org = user.profile.organization if hasattr(user, 'profile') else None
        
        pickup_lat = self.request.data.get('pickup_lat')
        pickup_lng = self.request.data.get('pickup_lng')
        dest_lat = self.request.data.get('dest_lat')
        dest_lng = self.request.data.get('dest_lng')
        
        pickup_point = Point(float(pickup_lng), float(pickup_lat), srid=4326) if pickup_lat and pickup_lng else None
        dest_point = Point(float(dest_lng), float(dest_lat), srid=4326) if dest_lat and dest_lng else None
        
        serializer.save(
            organization=org, 
            status='CREATED',
            pickup_location=pickup_point,
            destination=dest_point,
            request_lat=float(pickup_lat) if pickup_lat else None,
            request_lng=float(pickup_lng) if pickup_lng else None
        )

class DispatchRequestDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = DispatchRequestSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        qs = DispatchRequest.objects.all()
        if hasattr(user, 'profile') and user.profile.organization:
            qs = qs.filter(organization=user.profile.organization)
        return qs

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def dispatch_request_find_vehicles(request, pk):
    try:
        dispatch = DispatchRequest.objects.get(pk=pk)
    except DispatchRequest.DoesNotExist:
        return Response({'error': 'Dispatch request not found'}, status=404)
        
    # Execute Universal Dispatch Engine
    engine = DispatchEngine(dispatch)
    candidates = engine.execute()
    
    return Response({
        'dispatch': DispatchRequestSerializer(dispatch).data,
        'candidates': candidates
    })

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def dispatch_request_confirm(request, pk):
    try:
        dispatch = DispatchRequest.objects.get(pk=pk)
    except DispatchRequest.DoesNotExist:
        return Response({'error': 'Dispatch request not found'}, status=404)
        
    vehicle_id = request.data.get('vehicle_id')
    if not vehicle_id:
        return Response({'error': 'vehicle_id is required'}, status=400)
        
    try:
        vehicle = Vehicle.objects.get(pk=vehicle_id)
    except Vehicle.DoesNotExist:
        return Response({'error': 'Vehicle not found'}, status=404)
        
    # Mark vehicle as unavailable
    vehicle.is_available = False
    vehicle.save(update_fields=['is_available'])
    
    # Assign and update dispatch status
    dispatch.assigned_vehicle = vehicle
    dispatch.status = 'DISPATCHED'
    dispatch.assigned_at = timezone.now()
    dispatch.save(update_fields=['assigned_vehicle', 'status', 'assigned_at'])
    
    # Notify Driver
    if vehicle.driver and vehicle.driver.user:
        Notification.objects.create(
            user=vehicle.driver.user,
            notification_type='trip',
            title='New Dispatch Assigned',
            message=f'Vehicle {vehicle.name} has been assigned a {dispatch.get_request_type_display()} dispatch.',
            related_dispatch=dispatch,
        )
        
    return Response(DispatchRequestSerializer(dispatch).data)

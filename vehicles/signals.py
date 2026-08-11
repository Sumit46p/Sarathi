from django.db.models.signals import post_save
from django.dispatch import receiver

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from accounts.models import get_organization_name
from .models import Driver, Vehicle, DispatchRequest, Notification, IssueReport, EmergencyRequest, MaintenanceRecord
import re

def _get_org_group_name():
    try:
        org_name = get_organization_name()
        if org_name and org_name != 'Default Org':
            return 'org_notifications_' + re.sub(r'[^a-zA-Z0-9_\-]', '_', org_name.lower())
    except Exception:
        pass
    return "org_notifications_default_org"



@receiver(post_save, sender=Driver)
def _recompute_on_duty_change(sender, instance, **kwargs):
    """When a driver's duty status changes, refresh the assigned vehicle(s)."""
    for vehicle in instance.assigned_vehicles.all():
        vehicle.recompute_availability()


@receiver(post_save, sender=Vehicle)
def _recompute_on_vehicle_change(sender, instance, **kwargs):
    """When admin_blocked or driver assignment changes, refresh availability."""
    instance.recompute_availability()


@receiver(post_save, sender=DispatchRequest)
def _recompute_on_dispatch_change(sender, instance, **kwargs):
    """When a dispatch is created or its status changes, refresh the assigned vehicle's availability.

    Fires for any save on DispatchRequest, which covers:
    - dispatch creation (status moves to 'assigned')
    - driver/admin transition_to() calls (accepted, en_route, arrived, completed, cancelled)
    - the recurring .save() calls in transition_to()

    This ensures the vehicle becomes unavailable the moment a dispatch is created,
    and becomes available again the moment it reaches a terminal state.
    """
    if instance.assigned_vehicle is not None:
        instance.assigned_vehicle.recompute_availability()


@receiver(post_save, sender=Notification)
def _push_notification(sender, instance, created, **kwargs):
    """When a new notification is created, push it over WebSocket."""
    if not created:
        return
        
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'user_notifications_{instance.user_id}',
        {
            'type': 'send_notification',
            'payload': {
                'id': f'notification_{instance.id}',
                'type': instance.notification_type,
                'title': instance.title,
                'message': instance.message,
                'status': 'new',
                'timestamp': instance.created_at.isoformat(),
                'read': instance.is_read,
                'dispatch_id': instance.related_dispatch_id,
            }
        }
    )

@receiver(post_save, sender=IssueReport)
def _push_issue_report(sender, instance, created, **kwargs):
    """Push new or updated Issue Reports to the org admin channel."""
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        _get_org_group_name(),
        {
            'type': 'send_notification',
            'payload': {
                'id': f'issue_{instance.id}',
                'type': 'issue',
                'title': f'Issue: {instance.driver.assigned_vehicles.first().name if instance.driver.assigned_vehicles.exists() else "Unknown Vehicle"}',
                'message': instance.description,
                'status': instance.status,
                'timestamp': instance.created_at.isoformat(),
                'read': False,
            }
        }
    )

@receiver(post_save, sender=EmergencyRequest)
def _push_emergency_request(sender, instance, created, **kwargs):
    """Push Emergency SOS events to the org admin channel."""
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        _get_org_group_name(),
        {
            'type': 'send_notification',
            'payload': {
                'id': f'emergency_{instance.id}',
                'type': 'emergency',
                'title': f'Emergency: {instance.emergency_type}',
                'message': instance.description or 'Emergency assistance requested',
                'status': instance.status,
                'timestamp': instance.created_at.isoformat(),
                'read': False,
            }
        }
    )

@receiver(post_save, sender=MaintenanceRecord)
def _push_maintenance_record(sender, instance, created, **kwargs):
    """Push Maintenance events to the org admin channel."""
    if not created: return
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        _get_org_group_name(),
        {
            'type': 'send_notification',
            'payload': {
                'id': f'maintenance_{instance.id}',
                'type': 'admin',
                'title': f'Maintenance: {instance.vehicle.name}',
                'message': instance.maintenance_type,
                'status': 'new',
                'timestamp': getattr(instance, 'created_at', None) and instance.created_at.isoformat() or instance.due_date.isoformat(),
                'read': False,
            }
        }
    )

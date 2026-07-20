from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import Driver, Vehicle, DispatchRequest


@receiver(post_save, sender=Driver)
def _recompute_on_duty_change(sender, instance, **kwargs):
    """When a driver's duty status changes, refresh the assigned vehicle(s)."""
    for vehicle in instance.assigned_vehicles.all():
        vehicle.recompute_availability()


@receiver(post_save, sender=Vehicle)
def _recompute_on_vehicle_change(sender, instance, **kwargs):
    """When admin_blocked or driver assignment changes, refresh availability."""
    if instance.driver is not None:
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

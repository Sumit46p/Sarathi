from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import Driver, Vehicle


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

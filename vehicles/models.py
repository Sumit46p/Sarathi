from django.contrib.gis.db import models


class Vehicle(models.Model):
    """Represents a dispatchable vehicle with real-time location."""

    VEHICLE_TYPE_CHOICES = [
        ('ambulance', 'Ambulance'),
        ('logistics', 'Logistics'),
        ('municipal', 'Municipal'),
    ]

    name = models.CharField(max_length=100)
    vehicle_type = models.CharField(
        max_length=20,
        choices=VEHICLE_TYPE_CHOICES,
    )
    is_available = models.BooleanField(default=True)
    location = models.PointField(
        help_text='Current GPS location of the vehicle (lng, lat)',
    )

    def __str__(self):
        return f"{self.name} ({self.get_vehicle_type_display()})"

    class Meta:
        ordering = ['name']


class DispatchRequest(models.Model):
    """Tracks a dispatch request: which vehicle was assigned, where, and status."""

    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('assigned', 'Assigned'),
        ('completed', 'Completed'),
    ]

    request_lat = models.FloatField(help_text='Latitude of the dispatch request')
    request_lng = models.FloatField(help_text='Longitude of the dispatch request')
    vehicle_type = models.CharField(
        max_length=20,
        choices=Vehicle.VEHICLE_TYPE_CHOICES,
    )
    assigned_vehicle = models.ForeignKey(
        Vehicle,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='dispatch_requests',
    )
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='pending',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Dispatch #{self.pk} ({self.get_status_display()}) — {self.vehicle_type}"

    class Meta:
        ordering = ['-created_at']

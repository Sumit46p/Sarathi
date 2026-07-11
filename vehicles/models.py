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

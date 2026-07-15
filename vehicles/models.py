from django.contrib.gis.db import models
from django.utils import timezone


class Driver(models.Model):
    """Represents a driver that can be assigned to a vehicle."""
    name = models.CharField(max_length=100)
    phone_number = models.CharField(max_length=20)
    license_number = models.CharField(max_length=50, unique=True)
    is_active = models.BooleanField(default=True)
    owner = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='drivers',
    )

    def __str__(self):
        return f"{self.name} ({self.license_number})"


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
    number_plate = models.CharField(max_length=20, unique=True, null=True, blank=True)
    is_available = models.BooleanField(default=True)
    driver = models.ForeignKey(
        Driver,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='assigned_vehicles',
    )
    location = models.PointField(
        help_text='Current GPS location of the vehicle (lng, lat)',
    )
    # NEW: when we last received a GPS fix from this vehicle.
    # Null until the first update-location call. Indexed so the live-map
    # can cheaply query "stale" vehicles (no fix in N minutes).
    last_location_at = models.DateTimeField(
        null=True,
        blank=True,
        db_index=True,
        help_text='Last time a GPS update was received from this vehicle',
    )
    owner = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='vehicles',
    )

    def __str__(self):
        return f"{self.name} ({self.get_vehicle_type_display()})"

    @property
    def is_stale(self) -> bool:
        """True if no GPS update in the last 5 minutes."""
        if self.last_location_at is None:
            return True
        return (timezone.now() - self.last_location_at).total_seconds() > 300

    class Meta:
        ordering = ['name']


class DispatchRequest(models.Model):
    """Tracks a dispatch request through its full lifecycle.

    State machine:

        pending → assigned → accepted → en_route → arrived → completed
                  │           │
                  └→ rejected └→ cancelled   (also: any state → cancelled)

    - `pending`   : request created, no vehicle assigned yet
    - `assigned`  : vehicle selected + marked unavailable, driver notified
    - `accepted`  : driver acknowledged the dispatch
    - `rejected`  : driver declined (terminal — dispatcher files a new request)
    - `en_route`  : driver started moving toward the scene
    - `arrived`   : driver reached the scene   ← key analytics timestamp
    - `completed` : trip finished
    - `cancelled` : cancelled at any point (terminal)
    """

    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('assigned', 'Assigned'),
        ('accepted', 'Accepted'),
        ('rejected', 'Rejected'),
        ('en_route', 'En Route'),
        ('arrived', 'Arrived'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled'),
    ]

    # Valid forward transitions from each status.
    VALID_TRANSITIONS = {
        'pending':   ['assigned', 'cancelled'],
        'assigned':  ['accepted', 'rejected', 'cancelled'],
        'accepted':  ['en_route', 'cancelled'],
        'en_route':  ['arrived', 'cancelled'],
        'arrived':   ['completed', 'cancelled'],
        'completed': [],
        'rejected':  [],
        'cancelled': [],
    }

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
        db_index=True,
    )
    distance_km = models.FloatField(
        null=True, blank=True,
        help_text='Real road distance to assigned vehicle at dispatch time (OSRM)',
    )
    duration_min = models.FloatField(
        null=True, blank=True,
        help_text='Estimated travel time at dispatch time (OSRM), in minutes',
    )
    used_osrm = models.BooleanField(
        default=False,
        help_text='True if distance/duration came from OSRM; False if straight-line fallback',
    )

    # --- Lifecycle timestamps (all nullable for back-compat) ---
    created_at    = models.DateTimeField(auto_now_add=True)
    assigned_at   = models.DateTimeField(null=True, blank=True)
    accepted_at   = models.DateTimeField(null=True, blank=True)
    en_route_at   = models.DateTimeField(null=True, blank=True)
    arrived_at    = models.DateTimeField(null=True, blank=True)
    completed_at  = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"Dispatch #{self.pk} ({self.get_status_display()}) — {self.vehicle_type}"

    def transition_to(self, new_status: str) -> None:
        """Move to a new status, enforcing the state machine and stamping
        the corresponding timestamp. Raises ValueError on invalid transitions."""
        if new_status not in self.VALID_TRANSITIONS.get(self.status, []):
            raise ValueError(
                f"Invalid status transition: {self.status!r} → {new_status!r}"
            )
        now = timezone.now()
        self.status = new_status
        timestamp_field = {
            'assigned':  'assigned_at',
            'accepted':  'accepted_at',
            'en_route':  'en_route_at',
            'arrived':   'arrived_at',
            'completed': 'completed_at',
        }.get(new_status)
        if timestamp_field:
            setattr(self, timestamp_field, now)
        self.save(update_fields=['status', timestamp_field] if timestamp_field else ['status'])

    # --- Analytics helpers (used by the dashboard later) ---
    @property
    def response_time_seconds(self) -> float | None:
        """Dispatch-to-scene time. None if not arrived yet."""
        if self.assigned_at and self.arrived_at:
            return (self.arrived_at - self.assigned_at).total_seconds()
        return None

    @property
    def trip_duration_seconds(self) -> float | None:
        """Accepted-to-completed time. None if not completed."""
        if self.accepted_at and self.completed_at:
            return (self.completed_at - self.accepted_at).total_seconds()
        return None

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['status', 'created_at']),
            models.Index(fields=['vehicle_type', 'status']),
        ]

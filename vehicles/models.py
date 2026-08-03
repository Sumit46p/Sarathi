from django.contrib.gis.db import models
from django.utils import timezone


class Driver(models.Model):
    """Represents a driver that can be assigned to a vehicle."""
    name = models.CharField(max_length=100)
    phone_number = models.CharField(max_length=20)
    license_number = models.CharField(max_length=50, unique=True)
    is_active = models.BooleanField(default=True)
    requires_password_change = models.BooleanField(
        default=True,
        help_text='Forces driver to change password on first login.',
    )
    is_on_duty = models.BooleanField(
        default=False,
        db_index=True,
        help_text='Driver duty status. When True the assigned vehicle is available.',
    )
    owner = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='drivers',
    )
    user = models.OneToOneField(
        'auth.User',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='driver_profile',
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
    admin_blocked = models.BooleanField(
        default=False,
        help_text='Admin override. When True the vehicle is unavailable regardless of driver duty.',
    )
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
    total_distance_km = models.FloatField(
        default=0,
        help_text='Cumulative GPS-derived distance (approximate, not true odometer). Updated via location updates with noise filtering.',
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

    @property
    def has_active_dispatch(self) -> bool:
        """True if this vehicle has any dispatch request in a non-terminal state.

        Active dispatch states (anything not yet completed or cancelled):
        'assigned', 'accepted', 'en_route', 'arrived'.
        """
        return self.dispatch_requests.filter(
            status__in=['assigned', 'accepted', 'en_route', 'arrived']
        ).exists()

    @property
    def active_dispatch_status(self) -> str | None:
        """Returns the current status of an active dispatch, or None if no active dispatch."""
        active = self.dispatch_requests.filter(
            status__in=['assigned', 'accepted', 'en_route', 'arrived']
        ).order_by('-created_at').first()
        return active.status if active else None

    def recompute_availability(self) -> None:
        """Derive `is_available` from driver duty + admin block + active dispatch + driver online status.

        A vehicle is available if:
        - the vehicle is not admin-blocked, AND
        - the vehicle has no active dispatch in progress, AND
        - a driver is assigned AND the driver is on duty AND the driver app is actively online (last activity within 5 minutes)
        
        Uses a queryset update to avoid re-firing the post_save signal
        (which would recurse).
        """
        # If no driver assigned, vehicle is NOT available (cannot be dispatched)
        if not self.driver:
            is_available = False
        else:
            # Driver is assigned - check if they're on duty and online
            driver_online = False
            if self.driver.is_on_duty:
                # Check if driver has an active profile with recent app activity
                if hasattr(self.driver, 'user') and self.driver.user:
                    profile = getattr(self.driver.user, 'profile', None)
                    driver_online = profile.is_online if profile else False
            
            is_available = driver_online and not self.admin_blocked and not self.has_active_dispatch
        
        # Update database and refresh in-memory object
        updated_count = Vehicle.objects.filter(pk=self.pk).update(is_available=is_available)
        # Force refresh from database to ensure we have latest state
        if updated_count > 0:
            self.refresh_from_db()
        self.is_available = is_available

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


class IssueReport(models.Model):
    """A driver-submitted issue report with optional photo evidence."""

    STATUS_CHOICES = [
        ('open', 'Open'),
        ('acknowledged', 'Acknowledged'),
        ('resolved', 'Resolved'),
    ]

    driver = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name='issue_reports')
    description = models.TextField()
    image = models.ImageField(upload_to='issue_reports/', blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='open', db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"Issue by {self.driver.name} at {self.created_at}"


class MaintenanceRecord(models.Model):
    """Tracks maintenance history and schedules for a vehicle.
    
    Supports two types of recurrence:
    - recurrence_days: Calendar-based (e.g., every 30 days)
    - recurrence_km: Mileage-based (e.g., every 5000 km driven)
    
    When a maintenance is marked completed, the next due date is calculated
    as max(today + recurrence_days, current_km + recurrence_km) to allow
    whichever threshold is reached first to trigger the next maintenance.
    """

    MAINTENANCE_TYPE_CHOICES = [
        ('oil_change', 'Oil Change'),
        ('tire_rotation', 'Tire Rotation'),
        ('inspection', 'Inspection'),
        ('repair', 'Repair'),
        ('other', 'Other'),
    ]

    vehicle = models.ForeignKey(Vehicle, on_delete=models.CASCADE, related_name='maintenance_records')
    maintenance_type = models.CharField(max_length=50, choices=MAINTENANCE_TYPE_CHOICES)
    description = models.TextField(blank=True)
    due_date = models.DateField()
    completed = models.BooleanField(default=False)
    completed_at = models.DateTimeField(null=True, blank=True)
    # Recurrence rules - at least one should be set
    recurrence_days = models.IntegerField(
        null=True,
        blank=True,
        help_text='Repeat every N days (calendar-based recurrence)',
    )
    recurrence_km = models.IntegerField(
        null=True,
        blank=True,
        help_text='Repeat every N km driven (GPS-based recurrence)',
    )
    owner = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='maintenance_records',
    )
    image = models.ImageField(upload_to='maintenance_images/', null=True, blank=True)
    proof_image = models.ImageField(
        upload_to='maintenance_proofs/',
        null=True, blank=True,
        help_text='Photo evidence of completed maintenance',
    )
    completed_by = models.ForeignKey(
        'Driver',
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='completed_maintenance_records',
        help_text='Driver who completed this maintenance',
    )
    completion_notes = models.TextField(
        blank=True,
        help_text='Notes from the person who completed the maintenance',
    )
    cost = models.DecimalField(
        max_digits=10, decimal_places=2,
        null=True, blank=True,
        help_text='Cost of the maintenance in NPR',
    )

    def __str__(self):
        return f"{self.get_maintenance_type_display()} for {self.vehicle.name} due {self.due_date}"

    class Meta:
        ordering = ['due_date']
        indexes = [
            models.Index(fields=['vehicle', 'due_date']),
        ]

class MaintenanceTemplate(models.Model):
    """A reusable maintenance rule that can be applied to multiple vehicles.
    
    Allows admins to define a maintenance rule once (e.g., "Oil Change every 30 days
    or 5000 km") and apply it to one vehicle, multiple vehicles, or all vehicles
    of a specific type in the organization.
    """

    MAINTENANCE_TYPE_CHOICES = MaintenanceRecord.MAINTENANCE_TYPE_CHOICES

    name = models.CharField(max_length=100, help_text='Template name (e.g., "Standard Oil Change")')
    maintenance_type = models.CharField(max_length=50, choices=MAINTENANCE_TYPE_CHOICES)
    description = models.TextField(blank=True)
    recurrence_days = models.IntegerField(
        null=True,
        blank=True,
        help_text='Repeat every N days (optional)',
    )
    recurrence_km = models.IntegerField(
        null=True,
        blank=True,
        help_text='Repeat every N km driven (optional)',
    )
    owner = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='maintenance_templates',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} ({self.get_maintenance_type_display()})"

    class Meta:
        ordering = ['name']
        indexes = [
            models.Index(fields=['owner', 'created_at']),
        ]


class Notification(models.Model):
    """Persistent notification for a driver/user."""
    NOTIFICATION_TYPES = [
        ('trip', 'Trip'),
        ('issue', 'Issue'),
        ('admin', 'Admin'),
        ('system', 'System'),
    ]

    user = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='notifications',
        help_text='The user who receives this notification.',
    )
    notification_type = models.CharField(max_length=20, choices=NOTIFICATION_TYPES, default='system')
    title = models.CharField(max_length=200)
    message = models.TextField()
    related_dispatch = models.ForeignKey(
        'DispatchRequest',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='notifications',
    )
    related_issue = models.ForeignKey(
        'IssueReport',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='notifications',
    )
    is_read = models.BooleanField(default=False, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    def __str__(self):
        return f"{self.title} - {self.user.username}"

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'is_read', 'created_at']),
        ]


class EmergencyRequest(models.Model):
    """Represents an SOS/emergency request from a user."""
    EMERGENCY_TYPES = [
        ('medical', 'Medical Emergency'),
        ('accident', 'Accident'),
        ('breakdown', 'Vehicle Breakdown'),
        ('other', 'Other'),
    ]

    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('dispatched', 'Dispatched'),
        ('resolved', 'Resolved'),
        ('cancelled', 'Cancelled'),
    ]

    user = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='emergency_requests',
        help_text='The user who submitted the emergency request.',
    )
    emergency_type = models.CharField(max_length=20, choices=EMERGENCY_TYPES, default='other')
    description = models.TextField(blank=True)
    location = models.PointField(null=True, blank=True, help_text='Emergency location (lng, lat)')
    image = models.ImageField(upload_to='emergency_images/', null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending', db_index=True)
    assigned_vehicle = models.ForeignKey(
        'Vehicle',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='emergency_requests',
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"Emergency {self.emergency_type} - {self.user.username} - {self.status}"

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'status', 'created_at']),
            models.Index(fields=['status', 'created_at']),
        ]


class FuelEntry(models.Model):
    """Records a fuel fill-up event for a vehicle by a driver."""
    vehicle = models.ForeignKey(
        'Vehicle',
        on_delete=models.CASCADE,
        related_name='fuel_entries',
        help_text='The vehicle that was refuelled.',
    )
    driver = models.ForeignKey(
        'Driver',
        on_delete=models.CASCADE,
        related_name='fuel_entries',
        help_text='The driver who logged the fuel entry.',
    )
    liters = models.DecimalField(
        max_digits=8, decimal_places=2,
        help_text='Amount of fuel added in litres.',
    )
    cost_per_liter = models.DecimalField(
        max_digits=8, decimal_places=2,
        help_text='Price per litre in NPR.',
    )
    total_cost = models.DecimalField(
        max_digits=10, decimal_places=2,
        help_text='Total fuel cost in NPR.',
    )
    odometer_km = models.DecimalField(
        max_digits=10, decimal_places=1,
        null=True, blank=True,
        help_text='Odometer reading at the time of fuelling (km).',
    )
    notes = models.TextField(blank=True)
    fueled_at = models.DateTimeField(
        default=timezone.now,
        db_index=True,
        help_text='Date and time of the fuel fill-up.',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Fuel {self.liters}L – {self.vehicle.name} by {self.driver.name}"

    class Meta:
        ordering = ['-fueled_at']
        indexes = [
            models.Index(fields=['driver', 'fueled_at']),
            models.Index(fields=['vehicle', 'fueled_at']),
        ]


class FuelLog(models.Model):
    """Tracks fuel expenses for a vehicle with receipt proof."""
    FUEL_TYPE_CHOICES = [
        ('petrol', 'Petrol'),
        ('diesel', 'Diesel'),
    ]
    
    vehicle = models.ForeignKey(
        'Vehicle',
        on_delete=models.CASCADE,
        related_name='fuel_logs',
        help_text='The vehicle that was refuelled.',
    )
    driver = models.ForeignKey(
        'Driver',
        on_delete=models.CASCADE,
        related_name='fuel_logs',
        help_text='The driver who logged the fuel expense.',
    )
    fuel_type = models.CharField(
        max_length=10,
        choices=FUEL_TYPE_CHOICES,
        default='petrol',
        help_text='Type of fuel (Petrol or Diesel)',
    )
    liters = models.DecimalField(
        max_digits=8, decimal_places=2,
        null=True, blank=True,
        help_text='Volume of fuel in liters.',
    )
    amount = models.DecimalField(
        max_digits=10, decimal_places=2,
        help_text='Total fuel cost in NPR.',
    )
    cost_per_liter = models.DecimalField(
        max_digits=8, decimal_places=2,
        null=True, blank=True,
        help_text='Price per liter in NPR at time of entry.',
    )
    odometer_reading = models.DecimalField(
        max_digits=10, decimal_places=1,
        null=True, blank=True,
        help_text='Odometer reading at the time of fuelling (km).',
    )
    receipt_image = models.ImageField(
        upload_to='fuel_receipts/',
        null=True, blank=True,
        help_text='Photo of the fuel receipt.',
    )
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    def __str__(self):
        return f"FuelLog {self.amount} NPR – {self.vehicle.name} by {self.driver.name}"

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['driver', 'created_at']),
            models.Index(fields=['vehicle', 'created_at']),
        ]

class FuelPrice(models.Model):
    """Stores current fuel prices scraped from NOC (Nepal Oil Corporation)."""
    FUEL_TYPE_CHOICES = [
        ('petrol', 'Petrol'),
        ('diesel', 'Diesel'),
    ]
    
    fuel_type = models.CharField(
        max_length=10,
        choices=FUEL_TYPE_CHOICES,
        unique=True,
        help_text='Type of fuel.',
    )
    price_per_liter = models.DecimalField(
        max_digits=8, decimal_places=2,
        help_text='Current price per liter in NPR.',
    )
    last_updated = models.DateTimeField(
        auto_now=True,
        help_text='Last time this price was updated.',
    )
    source = models.CharField(
        max_length=100,
        default='NOC',
        help_text='Data source (e.g., NOC, manual).',
    )

    def __str__(self):
        return f"{self.get_fuel_type_display()}: रु {self.price_per_liter}/L"

    class Meta:
        verbose_name_plural = "Fuel Prices"
        ordering = ['fuel_type']

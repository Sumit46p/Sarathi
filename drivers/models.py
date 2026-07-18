from django.db import models


class DriverProfile(models.Model):
    """
    Stores driver data submitted from the Flutter signup screen.
    firebase_uid links this record to Firebase Auth without storing passwords.
    """
    firebase_uid = models.CharField(max_length=128, unique=True, db_index=True)
    name = models.CharField(max_length=255)
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=30, blank=True)
    vehicle_number = models.CharField(max_length=100, blank=True)
    department = models.CharField(max_length=100, blank=True)
    status = models.CharField(
        max_length=20,
        choices=[
            ('active', 'Active'),
            ('inactive', 'Inactive'),
            ('pending', 'Pending'),
        ],
        default='pending',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'driver_profiles'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.name} ({self.email})"


class DriverDocument(models.Model):
    """
    Records every document uploaded by a driver (license, ID, etc.).
    file_url can be a Firebase Storage URL or a local server path.
    """
    DOC_TYPE_CHOICES = [
        ('driving_license', 'Driving License'),
        ('national_id', 'National ID'),
        ('vehicle_registration', 'Vehicle Registration'),
        ('insurance', 'Insurance'),
        ('other', 'Other'),
    ]

    driver = models.ForeignKey(
        DriverProfile,
        on_delete=models.CASCADE,
        related_name='documents',
        to_field='firebase_uid',
    )
    doc_type = models.CharField(max_length=50, choices=DOC_TYPE_CHOICES, default='driving_license')
    file_url = models.TextField(help_text='Firebase Storage URL or local file path')
    file_name = models.CharField(max_length=255, blank=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'driver_documents'
        ordering = ['-uploaded_at']

    def __str__(self):
        return f"{self.driver.name} — {self.get_doc_type_display()}"


class LoginEvent(models.Model):
    """
    Records every login event from the Flutter app.
    Allows the admin dashboard to see driver activity history.
    """
    driver = models.ForeignKey(
        DriverProfile,
        on_delete=models.CASCADE,
        related_name='login_events',
        to_field='firebase_uid',
        null=True,
        blank=True,
    )
    firebase_uid = models.CharField(max_length=128, db_index=True)
    email = models.EmailField(blank=True)
    logged_in_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'driver_login_events'
        ordering = ['-logged_in_at']

    def __str__(self):
        return f"Login: {self.email} @ {self.logged_in_at:%Y-%m-%d %H:%M}"

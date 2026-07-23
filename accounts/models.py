from django.db import models
from django.contrib.auth.models import User
from vehicles.models import Vehicle

class Profile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    organization_name = models.CharField(max_length=255, default='Default Org')

    def __str__(self):
        return f"{self.user.username} Profile ({self.organization_name})"

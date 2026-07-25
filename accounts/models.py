from django.db import models
from django.contrib.auth.models import User
from vehicles.models import Vehicle

class Profile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    organization_name = models.CharField(max_length=255, default='Default Org')

    def __str__(self):
        return f"{self.user.username} Profile ({self.organization_name})"


def get_organization_name():
    """Return the canonical organization name for this deployment.

    Single source of truth: the admin registers the organization name once
    (as the very first user), and every other user in the deployment shares
    it. This avoids forcing drivers to know/re-type a per-user value (which
    previously defaulted to 'Default Org').

    Resolution order:
      1. The oldest profile with an explicitly-set org name (not 'Default Org')
         — i.e. the admin who configured the system.
      2. The oldest profile's org name (even if it still holds the default,
         e.g. during the very first registration).
      3. 'Default Org' as a last-resort fallback.
    """
    admin_profile = (
        Profile.objects
        .exclude(organization_name='Default Org')
        .select_related('user')
        .order_by('user__id')
        .first()
    )
    if admin_profile:
        return admin_profile.organization_name

    first_profile = Profile.objects.select_related('user').order_by('user__id').first()
    if first_profile:
        return first_profile.organization_name

    return 'Default Org'

from django.db.models.signals import post_save
from django.dispatch import receiver
from django.contrib.auth.models import User
from .models import Profile, get_organization_name


def _resolve_default_org():
    """Default new profiles to the admin's org name so drivers don't have to
    re-type it. Falls back to 'Default Org' when no admin exists yet
    (e.g. during the very first superuser creation)."""
    try:
        return get_organization_name()
    except Exception:
        return 'Default Org'


@receiver(post_save, sender=User)
def create_user_profile(sender, instance, created, **kwargs):
    """Auto-create Profile when User is created.

    New users (drivers, dispatchers) inherit the admin's organization name
    automatically — the admin sets it once, everyone shares it.
    """
    if created:
        Profile.objects.get_or_create(
            user=instance,
            defaults={'organization_name': _resolve_default_org()}
        )


@receiver(post_save, sender=User)
def save_user_profile(sender, instance, **kwargs):
    """Ensure Profile exists (for existing users without profile)"""
    if hasattr(instance, 'profile'):
        instance.profile.save()
    else:
        Profile.objects.get_or_create(
            user=instance,
            defaults={'organization_name': _resolve_default_org()}
        )
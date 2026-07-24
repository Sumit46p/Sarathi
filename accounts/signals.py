from django.db.models.signals import post_save
from django.dispatch import receiver
from django.contrib.auth.models import User
from .models import Profile

@receiver(post_save, sender=User)
def create_user_profile(sender, instance, created, **kwargs):
    """Auto-create Profile when User is created"""
    if created:
        Profile.objects.get_or_create(
            user=instance,
            defaults={'organization_name': 'Default Org'}
        )

@receiver(post_save, sender=User)
def save_user_profile(sender, instance, **kwargs):
    """Ensure Profile exists (for existing users without profile)"""
    if hasattr(instance, 'profile'):
        instance.profile.save()
    else:
        Profile.objects.get_or_create(
            user=instance,
            defaults={'organization_name': 'Default Org'}
        )
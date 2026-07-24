from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from accounts.models import Profile

class Command(BaseCommand):
    help = 'Create missing Profile records for users without profiles'

    def handle(self, *args, **options):
        users_without_profile = User.objects.filter(profile__isnull=True)
        count = 0
        
        for user in users_without_profile:
            Profile.objects.get_or_create(
                user=user,
                defaults={'organization_name': 'Default Org'}
            )
            count += 1
            self.stdout.write(
                self.style.SUCCESS(
                    f'[OK] Created profile for user: {user.username}'
                )
            )
        
        self.stdout.write(
            self.style.SUCCESS(
                f'\nFixed {count} users with missing profiles'
            )
        )
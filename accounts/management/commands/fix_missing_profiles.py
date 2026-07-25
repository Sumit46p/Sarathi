from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from accounts.models import Profile, get_organization_name


class Command(BaseCommand):
    help = (
        'Create missing Profile records and align every profile\'s '
        'organization_name with the admin\'s canonical org name.'
    )

    def handle(self, *args, **options):
        canonical_org = get_organization_name()
        self.stdout.write(f'Canonical organization name: "{canonical_org}"')

        # 1) Create profiles for users without one
        created_count = 0
        for user in User.objects.filter(profile__isnull=True):
            Profile.objects.get_or_create(
                user=user,
                defaults={'organization_name': canonical_org},
            )
            created_count += 1
            self.stdout.write(
                self.style.SUCCESS(
                    f'[OK] Created profile for user: {user.username}'
                )
            )

        # 2) Sync existing profiles to the canonical org name.
        #    Skip the single profile whose org name is the source of truth
        #    (the oldest profile carrying the canonical name — i.e. the admin).
        admin_profile = (
            Profile.objects
            .filter(organization_name=canonical_org)
            .select_related('user')
            .order_by('user__id')
            .first()
        )
        admin_user_id = admin_profile.user_id if admin_profile else None

        synced_count = 0
        for profile in Profile.objects.exclude(organization_name=canonical_org):
            if profile.user_id == admin_user_id:
                continue
            old = profile.organization_name
            profile.organization_name = canonical_org
            profile.save(update_fields=['organization_name'])
            synced_count += 1
            self.stdout.write(
                self.style.SUCCESS(
                    f'[OK] Synced {profile.user.username}: '
                    f'"{old}" -> "{canonical_org}"'
                )
            )

        self.stdout.write(
            self.style.SUCCESS(
                f'\nDone. Created {created_count} missing profile(s), '
                f'synced {synced_count} profile(s) to "{canonical_org}".'
            )
        )

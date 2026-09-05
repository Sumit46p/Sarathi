from django.db import migrations, models


class Migration(migrations.Migration):
    """
    Expand VEHICLE_TYPE_CHOICES to universal fleet categories.
    Removes: ambulance, municipal (both now fall under 'government').
    Adds: rental, government, company, personal, public_transport, commercial.
    choices= is metadata-only in Django - no column type change needed.
    """

    dependencies = [
        ('vehicles', '0032_dispatchrequest_destination_and_more'),
    ]

    operations = [
        migrations.AlterField(
            model_name='vehicle',
            name='vehicle_type',
            field=models.CharField(
                max_length=20,
                choices=[
                    ('rental', 'Rental Vehicle'),
                    ('government', 'Government Vehicle'),
                    ('company', 'Company Vehicle'),
                    ('personal', 'Personal Vehicle'),
                    ('logistics', 'Logistics'),
                    ('public_transport', 'Public Transport'),
                    ('commercial', 'Commercial / Construction'),
                ],
            ),
        ),
        migrations.AlterField(
            model_name='dispatchrequest',
            name='vehicle_type',
            field=models.CharField(
                max_length=20,
                choices=[
                    ('rental', 'Rental Vehicle'),
                    ('government', 'Government Vehicle'),
                    ('company', 'Company Vehicle'),
                    ('personal', 'Personal Vehicle'),
                    ('logistics', 'Logistics'),
                    ('public_transport', 'Public Transport'),
                    ('commercial', 'Commercial / Construction'),
                ],
            ),
        ),
    ]

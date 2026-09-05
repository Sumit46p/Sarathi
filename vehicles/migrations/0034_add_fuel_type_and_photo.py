from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('vehicles', '0033_expand_fleet_vehicle_types'),
    ]

    operations = [
        migrations.AddField(
            model_name='vehicle',
            name='fuel_type',
            field=models.CharField(
                max_length=20,
                choices=[('petrol', 'Petrol'), ('diesel', 'Diesel'), ('ev', 'EV')],
                null=True,
                blank=True,
            ),
        ),
        migrations.AddField(
            model_name='vehicle',
            name='photo',
            field=models.ImageField(
                upload_to='vehicles/photos/',
                null=True,
                blank=True,
                help_text='Photo or icon of the vehicle for map tracking',
            ),
        ),
    ]

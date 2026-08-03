# Generated manually to migrate old FuelEntry data to FuelLog

from django.db import migrations


def migrate_fuelentry_to_fuellog(apps, schema_editor):
    """Copy data from old FuelEntry model to new FuelLog model."""
    FuelEntry = apps.get_model('vehicles', 'FuelEntry')
    FuelLog = apps.get_model('vehicles', 'FuelLog')
    
    for entry in FuelEntry.objects.all():
        # Check if this entry already exists in FuelLog (avoid duplicates)
        existing = FuelLog.objects.filter(
            driver=entry.driver,
            vehicle=entry.vehicle,
            created_at=entry.created_at
        ).exists()
        
        if not existing:
            FuelLog.objects.create(
                vehicle=entry.vehicle,
                driver=entry.driver,
                fuel_type='petrol',  # Default to petrol since old model didn't have fuel_type
                liters=entry.liters,
                amount=entry.total_cost,
                cost_per_liter=entry.cost_per_liter,
                odometer_reading=entry.odometer_km,
                notes=entry.notes,
                receipt_image='',  # Old model didn't have receipt images
                created_at=entry.fueled_at,
            )


def reverse_migration(apps, schema_editor):
    """Remove migrated FuelLog entries (optional - be careful with this)."""
    # We won't delete FuelLog entries in reverse as they might have been created independently
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('vehicles', '0020_add_fuel_prices_and_fields'),
    ]

    operations = [
        migrations.RunPython(migrate_fuelentry_to_fuellog, reverse_migration),
    ]
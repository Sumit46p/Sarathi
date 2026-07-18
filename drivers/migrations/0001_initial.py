from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='DriverProfile',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('firebase_uid', models.CharField(db_index=True, max_length=128, unique=True)),
                ('name', models.CharField(max_length=255)),
                ('email', models.EmailField(max_length=254, unique=True)),
                ('phone', models.CharField(blank=True, max_length=30)),
                ('vehicle_number', models.CharField(blank=True, max_length=100)),
                ('department', models.CharField(blank=True, max_length=100)),
                ('status', models.CharField(
                    choices=[('active', 'Active'), ('inactive', 'Inactive'), ('pending', 'Pending')],
                    default='pending',
                    max_length=20,
                )),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'db_table': 'driver_profiles',
                'ordering': ['-created_at'],
            },
        ),
        migrations.CreateModel(
            name='DriverDocument',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('driver', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='documents',
                    to='drivers.driverprofile',
                    to_field='firebase_uid',
                )),
                ('doc_type', models.CharField(
                    choices=[
                        ('driving_license', 'Driving License'),
                        ('national_id', 'National ID'),
                        ('vehicle_registration', 'Vehicle Registration'),
                        ('insurance', 'Insurance'),
                        ('other', 'Other'),
                    ],
                    default='driving_license',
                    max_length=50,
                )),
                ('file_url', models.TextField(help_text='Firebase Storage URL or local file path')),
                ('file_name', models.CharField(blank=True, max_length=255)),
                ('uploaded_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={
                'db_table': 'driver_documents',
                'ordering': ['-uploaded_at'],
            },
        ),
        migrations.CreateModel(
            name='LoginEvent',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('driver', models.ForeignKey(
                    blank=True,
                    null=True,
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='login_events',
                    to='drivers.driverprofile',
                    to_field='firebase_uid',
                )),
                ('firebase_uid', models.CharField(db_index=True, max_length=128)),
                ('email', models.EmailField(blank=True, max_length=254)),
                ('logged_in_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={
                'db_table': 'driver_login_events',
                'ordering': ['-logged_in_at'],
            },
        ),
    ]

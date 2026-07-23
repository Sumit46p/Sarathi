from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        (('vehicles', '0011_driver_requires_password_change')),
    ]

    operations = [
        migrations.CreateModel(
            name='IssueReport',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('description', models.TextField()),
                ('image', models.ImageField(blank=True, null=True, upload_to='issue_reports/')),
                ('resolved', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('driver', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='issue_reports', to='vehicles.driver')),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
    ]

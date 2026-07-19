from django.apps import AppConfig


class VehiclesConfig(AppConfig):
    name = 'vehicles'

    def ready(self):
        from . import signals  # noqa: F401

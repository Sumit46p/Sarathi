from django.urls import path
from . import views

app_name = 'vehicles'

urlpatterns = [
    path('vehicles/', views.VehicleListCreateView.as_view(), name='vehicle-list'),
    path('vehicles/nearest/', views.nearest_vehicles, name='vehicle-nearest'),
    path('vehicles/<int:pk>/', views.VehicleDetailView.as_view(), name='vehicle-detail'),
    path('vehicles/<int:pk>/update-location/', views.update_location, name='vehicle-update-location'),
    path('vehicles/<int:pk>/assign-driver/', views.assign_driver, name='vehicle-assign-driver'),
    path('drivers/', views.DriverListCreateView.as_view(), name='driver-list'),
    path('drivers/<int:pk>/', views.DriverDetailView.as_view(), name='driver-detail'),
    path('dispatch/', views.dispatch_vehicle, name='dispatch'),
    path('maintenance/', views.MaintenanceRecordListCreateView.as_view(), name='maintenance-list'),
    path('maintenance/<int:pk>/', views.MaintenanceRecordDetailView.as_view(), name='maintenance-detail'),
    path('maintenance/upcoming/', views.upcoming_maintenance, name='maintenance-upcoming'),
]

from django.urls import path
from . import views

app_name = 'vehicles'

urlpatterns = [
    path('vehicles/', views.VehicleListCreateView.as_view(), name='vehicle-list'),
    path('vehicles/nearest/', views.nearest_vehicles, name='vehicle-nearest'),
    path('vehicles/<int:pk>/', views.VehicleDetailView.as_view(), name='vehicle-detail'),
    path('vehicles/<int:pk>/update-location/', views.update_location, name='vehicle-update-location'),
    path('dispatch/', views.dispatch_vehicle, name='dispatch'),
]

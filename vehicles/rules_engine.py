from django.utils import timezone
from .models import Rule, Alert

def evaluate_rules(vehicle, trip, location_record):
    """
    Evaluates all active rules for the vehicle's fleet/organization against the current GPS location/trip.
    Generates Alerts if rules are violated.
    """
    if not vehicle.organization:
        return

    # Gather applicable rules (Fleet specific or Org-wide)
    rules = Rule.objects.filter(
        organization=vehicle.organization,
        enabled=True
    )
    if vehicle.fleet:
        rules = rules.filter(fleet=vehicle.fleet)

    for rule in rules:
        if rule.rule_type == 'SPEED_LIMIT':
            max_speed = rule.configuration.get('max_speed_kmh', 100)
            if location_record.speed_kmh > max_speed:
                Alert.objects.create(
                    organization=vehicle.organization,
                    vehicle=vehicle,
                    trip=trip,
                    rule=rule,
                    alert_type='SPEED_LIMIT',
                    severity=rule.severity,
                    message=f"Vehicle exceeded speed limit: {location_record.speed_kmh} km/h (Limit: {max_speed})",
                    location=location_record.location,
                )
        
        elif rule.rule_type == 'GEOFENCE':
            # configuration should contain {"polygon": "..."} (WKT) or GeoJSON.
            # Simplified for implementation plan: if PostGIS is enabled, use geometry check.
            pass
            
        elif rule.rule_type == 'ROUTE_DEVIATION':
            # Check deviation against trip route
            pass
        
        elif rule.rule_type == 'UNAUTHORIZED_USE':
            if not trip and location_record.speed_kmh > 0:
                # Vehicle moving without an active trip!
                Alert.objects.create(
                    organization=vehicle.organization,
                    vehicle=vehicle,
                    rule=rule,
                    alert_type='UNAUTHORIZED_USE',
                    severity=rule.severity,
                    message="Vehicle is moving without an active trip assignment.",
                    location=location_record.location,
                )

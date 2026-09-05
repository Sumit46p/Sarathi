import math
from django.utils import timezone
from .models import Vehicle, DispatchRequest
from .osrm import get_route_distance

def haversine(lat1, lon1, lat2, lon2):
    """Calculates great-circle distance between two points in km."""
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c

class DispatchCandidate:
    def __init__(self, vehicle, distance_km, eta_min, score, reason, route_geometry=None, request=None):
        self.vehicle = vehicle
        self.distance_km = distance_km
        self.eta_min = eta_min
        self.score = score
        self.reason = reason
        self.route_geometry = route_geometry
        self.request = request

    def to_dict(self):
        photo_url = None
        if self.vehicle.photo:
            try:
                photo_url = self.request.build_absolute_uri(self.vehicle.photo.url) if self.request else self.vehicle.photo.url
            except Exception:
                photo_url = self.vehicle.photo.url

        driver_info = None
        if self.vehicle.driver:
            driver_info = {
                'id': self.vehicle.driver.id,
                'name': self.vehicle.driver.name,
                'phone_number': self.vehicle.driver.phone_number,
                'license_number': self.vehicle.driver.license_number,
                'is_on_duty': self.vehicle.driver.is_on_duty,
            }

        return {
            'vehicle_id': self.vehicle.id,
            'vehicle_name': self.vehicle.name,
            'number_plate': self.vehicle.number_plate or 'No Plate',
            'vehicle_type': self.vehicle.vehicle_type,
            'fuel_type': self.vehicle.fuel_type,
            'photo_url': photo_url,
            'current_location': {
                'lat': self.vehicle.location.y if self.vehicle.location else None,
                'lng': self.vehicle.location.x if self.vehicle.location else None,
            },
            'driver': driver_info,
            'distance_km': round(self.distance_km, 2),
            'eta_min': round(self.eta_min, 1) if self.eta_min is not None else None,
            'score': round(self.score, 1),
            'reason': self.reason,
            'is_available': self.vehicle.is_available,
            'vehicle_status': getattr(self.vehicle, 'vehicle_status', 'available'),
            'route_geometry': self.route_geometry,
        }

class DispatchEngine:
    """
    Deterministic, rule-based dispatch engine for Sarathi Fleet Management.
    
    Workflow & Rules:
    1. Mandatory Vehicle Type Match: Only vehicles of exact requested vehicle_type are evaluated.
    2. Availability Filtering: Vehicle must be available, not admin-blocked, driver must be on-duty,
       and vehicle must not be on an active dispatch.
    3. Rule-Based Ranking: ETA (estimated real-road travel time) is the PRIMARY factor.
       Travel time is prioritized over straight geographic distance.
    4. Emergency Prioritization: Emergency requests apply higher ETA weighting and strict response rules.
    5. Explainable Recommendations: Generates human-readable, deterministic rationale for the recommendation.
    6. Diagnostics on Failure: Gathers nearby busy/offline vehicles and active dispatches for admin escalation.
    """

    def __init__(self, target_lat, target_lng, vehicle_type, request_type='NORMAL', priority='MEDIUM', organization=None, http_request=None):
        self.target_lat = float(target_lat)
        self.target_lng = float(target_lng)
        self.vehicle_type = vehicle_type
        self.request_type = (request_type or 'NORMAL').upper()
        self.priority = (priority or 'MEDIUM').upper()
        self.organization = organization
        self.http_request = http_request

        # Rule weighting configuration
        if self.request_type == 'EMERGENCY':
            # Emergency heavily penalizes long ETA
            self.weight_eta = 0.65
            self.weight_distance = 0.20
            self.weight_readiness = 0.15
        else:
            # Normal logistics/rental dispatch
            self.weight_eta = 0.45
            self.weight_distance = 0.35
            self.weight_readiness = 0.20

    @classmethod
    def from_dispatch_request(cls, dispatch_req, http_request=None):
        lat = dispatch_req.request_lat or (dispatch_req.pickup_location.y if dispatch_req.pickup_location else 0.0)
        lng = dispatch_req.request_lng or (dispatch_req.pickup_location.x if dispatch_req.pickup_location else 0.0)
        return cls(
            target_lat=lat,
            target_lng=lng,
            vehicle_type=dispatch_req.vehicle_type,
            request_type=dispatch_req.request_type,
            priority=dispatch_req.priority,
            organization=dispatch_req.organization,
            http_request=http_request,
        )

    def evaluate(self):
        """
        Runs the rule-based filtering and ranking pipeline.
        Returns:
            recommended: DispatchCandidate or None
            candidates: List[DispatchCandidate] (sorted descending by score)
            diagnostics: Dict containing diagnostic info if no suitable vehicle found
        """
        # Step 1: Query compatible vehicles matching requested vehicle_type
        eligible_vehicles = self._filter_eligible_vehicles()

        if not eligible_vehicles:
            diagnostics = self._generate_diagnostics()
            return None, [], diagnostics

        # Step 2: Rank eligible vehicles using road routing (OSRM) and rule scoring
        ranked_candidates = self._rank_vehicles(eligible_vehicles)

        if not ranked_candidates:
            diagnostics = self._generate_diagnostics()
            return None, [], diagnostics

        recommended = ranked_candidates[0]
        other_candidates = ranked_candidates[1:]

        return recommended, other_candidates, None

    def _filter_eligible_vehicles(self):
        """
        Applies mandatory filters:
        - Exact vehicle_type match (Rule 3)
        - is_available = True
        - admin_blocked = False
        - driver assigned and on duty (is_on_duty = True)
        - not under maintenance / offline
        - has GPS location
        - not currently on active dispatch
        """
        qs = Vehicle.objects.filter(
            vehicle_type=self.vehicle_type,
            is_available=True,
            admin_blocked=False,
            location__isnull=False,
        ).select_related('driver', 'driver__user', 'organization')

        if self.organization:
            qs = qs.filter(organization=self.organization)

        candidates = []
        for vehicle in qs:
            # Must have an active driver on duty
            if not vehicle.driver or not vehicle.driver.is_active or not vehicle.driver.is_on_duty:
                continue

            # Must not have an active ongoing dispatch
            if vehicle.has_active_dispatch:
                continue

            # Check status if present
            v_status = getattr(vehicle, 'vehicle_status', 'available')
            if v_status in ['maintenance', 'offline', 'rented', 'in_use', 'on_route']:
                continue

            candidates.append(vehicle)

        return candidates

    def _rank_vehicles(self, vehicles):
        """
        Calculates road-based travel time (ETA) and distance for each candidate.
        Ranks by score where lower ETA gets higher score.
        """
        candidates = []

        for vehicle in vehicles:
            origin_lat = vehicle.location.y
            origin_lng = vehicle.location.x

            # Real road calculation via OSRM
            dist_km, eta_min, geom = get_route_distance(
                origin_lat, origin_lng, self.target_lat, self.target_lng
            )

            # Fallback to Haversine if OSRM unavailable
            if dist_km is None:
                dist_km = haversine(origin_lat, origin_lng, self.target_lat, self.target_lng)
                avg_speed_kmh = 35.0 if self.request_type == 'NORMAL' else 45.0
                eta_min = (dist_km / avg_speed_kmh) * 60.0

            # Discard vehicles farther than 150 km for local response
            if dist_km > 150.0:
                continue

            score, reason = self._compute_score_and_reason(vehicle, dist_km, eta_min)

            candidates.append(
                DispatchCandidate(
                    vehicle=vehicle,
                    distance_km=dist_km,
                    eta_min=eta_min,
                    score=score,
                    reason=reason,
                    route_geometry=geom,
                    request=self.http_request,
                )
            )

        # Sort descending by score (highest score first)
        candidates.sort(key=lambda c: c.score, reverse=True)
        return candidates

    def _compute_score_and_reason(self, vehicle, dist_km, eta_min):
        """
        Computes normalized score (0 to 100) and human-readable explanation.
        ETA is prioritized over geographic distance.
        """
        # Baseline ideal: ETA = 0 min (score 100)
        # 10 min ETA loses ~20 points; 30 min ETA loses ~60 points
        eta_penalty = min(80.0, (eta_min / 40.0) * 100.0 * self.weight_eta)
        dist_penalty = min(40.0, (dist_km / 50.0) * 100.0 * self.weight_distance)

        score = max(5.0, 100.0 - eta_penalty - dist_penalty)

        # Emergency responsiveness bonus if under 10 minutes
        if self.request_type == 'EMERGENCY' and eta_min <= 10.0:
            score = min(100.0, score + 15.0)

        # Generate deterministic reason
        reason_parts = []
        if self.request_type == 'EMERGENCY':
            if eta_min <= 8.0:
                reason_parts.append(f"Fastest emergency response ({round(eta_min, 1)} mins ETA)")
            else:
                reason_parts.append(f"Lowest response time ({round(eta_min, 1)} mins ETA) among compatible units")
            reason_parts.append(f"Road distance: {round(dist_km, 1)} km")
        else:
            if eta_min <= 12.0:
                reason_parts.append(f"Lowest estimated travel time ({round(eta_min, 1)} mins)")
            else:
                reason_parts.append(f"Optimal road route ({round(eta_min, 1)} mins, {round(dist_km, 1)} km)")

        if vehicle.driver:
            reason_parts.append(f"Driver {vehicle.driver.name} is on duty & ready")

        return score, ". ".join(reason_parts) + "."

    def _generate_diagnostics(self):
        """
        Gathers detailed diagnostic information when no compatible vehicle is available (Requirement 9 & 13):
        - Nearby unavailable vehicles of requested type
        - Vehicles on active assignment with estimated remaining time
        - Alternative vehicle types available in fleet
        - Escalation options
        """
        nearby_unavailable = []
        active_assignments = []

        all_type_vehicles = Vehicle.objects.filter(
            vehicle_type=self.vehicle_type
        ).select_related('driver')

        if self.organization:
            all_type_vehicles = all_type_vehicles.filter(organization=self.organization)

        for v in all_type_vehicles:
            dist = None
            if v.location:
                dist = round(haversine(v.location.y, v.location.x, self.target_lat, self.target_lng), 1)

            # Determine reason for unavailability
            unavailability_reasons = []
            if v.admin_blocked:
                unavailability_reasons.append("Admin blocked")
            if not v.driver:
                unavailability_reasons.append("No driver assigned")
            elif not v.driver.is_on_duty:
                unavailability_reasons.append(f"Driver {v.driver.name} is off duty")
            if getattr(v, 'vehicle_status', '') == 'maintenance':
                unavailability_reasons.append("Under maintenance")

            # Check active dispatch
            active_disp = DispatchRequest.objects.filter(
                assigned_vehicle=v,
                status__in=['assigned', 'accepted', 'en_route', 'arrived', 'DISPATCHED', 'RESPONDING', 'IN_PROGRESS']
            ).order_by('-assigned_at').first()

            if active_disp:
                active_assignments.append({
                    'vehicle_id': v.id,
                    'vehicle_name': v.name,
                    'number_plate': v.number_plate,
                    'driver_name': v.driver.name if v.driver else 'Unassigned',
                    'current_dispatch_status': active_disp.get_status_display() if hasattr(active_disp, 'get_status_display') else active_disp.status,
                    'assigned_at': active_disp.assigned_at.strftime('%H:%M') if active_disp.assigned_at else None,
                    'destination': active_disp.location_name or 'Incident Area',
                })
            else:
                nearby_unavailable.append({
                    'vehicle_id': v.id,
                    'vehicle_name': v.name,
                    'number_plate': v.number_plate,
                    'distance_km': dist,
                    'reason': ", ".join(unavailability_reasons) or "Unavailable",
                })

        # Alternative vehicle categories that ARE currently available
        available_other_types = list(
            Vehicle.objects.filter(is_available=True, admin_blocked=False)
            .exclude(vehicle_type=self.vehicle_type)
            .values_list('vehicle_type', flat=True)
            .distinct()
        )

        return {
            'error_title': 'No suitable vehicle is currently available',
            'requested_vehicle_type': self.vehicle_type,
            'is_emergency': self.request_type == 'EMERGENCY',
            'nearby_unavailable_vehicles': nearby_unavailable,
            'active_dispatches': active_assignments,
            'alternative_available_types': available_other_types,
            'escalation_advice': (
                "EMERGENCY ESCALATION: All units of this type are occupied or off duty. "
                "Contact fleet dispatcher or mutual aid partners immediately."
                if self.request_type == 'EMERGENCY'
                else "No available units found. Consider adjusting vehicle type or recalling an off-duty unit."
            ),
        }

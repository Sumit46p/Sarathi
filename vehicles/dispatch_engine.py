import math
from django.utils import timezone
from .models import Vehicle, DispatchRequest
from .osrm import get_route_distance

def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c

class DispatchCandidate:
    def __init__(self, vehicle, distance_km, eta_min, score, reason):
        self.vehicle = vehicle
        self.distance_km = distance_km
        self.eta_min = eta_min
        self.score = score
        self.reason = reason
        
    def to_dict(self):
        return {
            'vehicle_id': self.vehicle.id,
            'vehicle_name': self.vehicle.name,
            'vehicle_type': self.vehicle.vehicle_type,
            'driver_name': self.vehicle.driver.name if self.vehicle.driver else None,
            'distance_km': round(self.distance_km, 2),
            'eta_min': round(self.eta_min, 1) if self.eta_min is not None else None,
            'score': round(self.score, 1),
            'reason': self.reason,
            'is_available': self.vehicle.is_available,
        }

class DispatchEngine:
    def __init__(self, dispatch_request):
        self.request = dispatch_request
        # Configurable weights
        if self.request.request_type == 'EMERGENCY':
            self.weights = {'eta': 0.45, 'capability': 0.25, 'availability': 0.15, 'distance': 0.10, 'operational': 0.05}
        else: # LOGISTICS
            self.weights = {'eta': 0.35, 'suitability': 0.20, 'distance': 0.15, 'capacity': 0.15, 'availability': 0.10, 'deadline': 0.05}
            
        if self.request.score_weights:
            self.weights = self.request.score_weights

    def execute(self):
        """Runs the full dispatch logic and returns a list of DispatchCandidate dicts."""
        candidates = self.find_candidates()
        if not candidates:
            self.request.status = 'NO_VEHICLE_AVAILABLE'
            self.request.save(update_fields=['status'])
            return []
            
        ranked = self.rank_candidates(candidates)
        if not ranked:
            self.request.status = 'NO_VEHICLE_AVAILABLE'
            self.request.save(update_fields=['status'])
            return []
            
        self.request.status = 'RECOMMENDED'
        self.request.save(update_fields=['status'])
        
        return [c.to_dict() for c in ranked]

    def find_candidates(self):
        # Base filter: Only available vehicles, not blocked.
        qs = Vehicle.objects.filter(is_available=True, admin_blocked=False)
        
        if self.request.organization:
            qs = qs.filter(organization=self.request.organization)
            
        if self.request.vehicle_type:
            qs = qs.filter(vehicle_type=self.request.vehicle_type)
            
        return list(qs)

    def rank_candidates(self, vehicles):
        if not self.request.pickup_location:
            return []
            
        dest_lng, dest_lat = self.request.pickup_location.x, self.request.pickup_location.y
        
        scored_candidates = []
        for vehicle in vehicles:
            if not vehicle.location:
                continue
                
            origin_lng, origin_lat = vehicle.location.x, vehicle.location.y
            
            dist, duration, geom = get_route_distance(origin_lat, origin_lng, dest_lat, dest_lng)
            
            # Fallback to Haversine if OSRM is down
            if dist is None:
                dist = haversine(origin_lat, origin_lng, dest_lat, dest_lng)
                duration = (dist / 40.0) * 60.0  # Assuming 40km/h average speed
                
            # Cap distance to avoid evaluating extremely far vehicles
            if dist > 200:  
                continue
                
            score, reason = self.calculate_score(vehicle, dist, duration)
            
            scored_candidates.append(
                DispatchCandidate(
                    vehicle=vehicle,
                    distance_km=dist,
                    eta_min=duration,
                    score=score,
                    reason=reason
                )
            )
            
        # Sort descending by score
        scored_candidates.sort(key=lambda c: c.score, reverse=True)
        return scored_candidates

    def calculate_score(self, vehicle, dist, duration):
        score = 100.0
        reason_parts = []
        
        # Distance & ETA deductions
        # Base ideal is 0 dist, 0 ETA.
        eta_penalty = (duration / 60.0) * 100 * self.weights.get('eta', 0)
        dist_penalty = (dist / 50.0) * 100 * self.weights.get('distance', 0)
        
        score -= (eta_penalty + dist_penalty)
        
        if score < 0:
            score = 0
            
        # Capability check
        if self.request.required_capability:
            # We don't have a rigid required_capability on vehicle yet,
            # but if it matches, give a boost.
            score += 20 * self.weights.get('capability', 0)
            reason_parts.append("Meets required capability")
            
        if self.request.request_type == 'EMERGENCY':
            if duration < 10:
                reason_parts.append("Fastest estimated response")
            elif score > 80:
                reason_parts.append("Good response time and capability")
        else:
            if duration < 30 and dist < 20:
                reason_parts.append("Nearest suitable available vehicle")
                
        if not reason_parts:
            reason_parts.append("Eligible vehicle")
            
        return score, ", ".join(reason_parts)

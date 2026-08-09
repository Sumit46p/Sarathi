import { api } from './auth';

export interface Vehicle {
  id: number;
  name: string;
  vehicle_type: 'ambulance' | 'logistics' | 'municipal';
  is_available: boolean;
  location: {
    lat: number;
    lng: number;
  };
}

export interface AnalyticsData {
  fleet_status: Array<{ name: string; value: number; color: string }>;
  dispatch_volume: Array<{ day: string; count: number }>;
  emergency_trends: Array<{ day: string; count: number }>;
  vehicle_type_dist: Array<{ name: string; value: number; color: string }>;
  top_drivers: Array<{ name: string; completed: number }>;
  issue_breakdown: Array<{ name: string; value: number; color: string }>;
  fuel_trends: Array<{ day: string; cost: number; liters: number }>;
  vehicle_efficiency: Array<{ vehicle_id: number; distance_km: number; liters: number; km_per_liter: number }>;
  driver_performance: Array<{
    name: string;
    total_trips: number;
    accepted_trips: number;
    acceptance_rate: number;
    completed_trips: number;
    score: number;
    harsh_events: number;
    events: { harsh_accel: number; harsh_brake: number; harsh_turn: number; total: number };
  }>;
  kpi: {
    total_vehicles: number;
    available: number;
    total_drivers: number;
    active_drivers: number;
    total_dispatches: number;
    completed_dispatches: number;
    pending_emergencies: number;
    open_issues: number;
    avg_response_time_min: number | null;
    total_fuel_cost: number;
  };
}

export async function fetchVehicles(): Promise<Vehicle[]> {
  const { data } = await api.get<Vehicle[]>('/vehicles/');
  return data;
}

export async function fetchAnalytics(): Promise<AnalyticsData> {
  const { data } = await api.get<AnalyticsData>('/analytics/dashboard/');
  return data;
}

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

export async function fetchVehicles(): Promise<Vehicle[]> {
  const { data } = await api.get<Vehicle[]>('/vehicles/');
  return data;
}

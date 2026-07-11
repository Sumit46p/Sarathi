import axios from 'axios';

const API_BASE = 'http://127.0.0.1:8000/api';

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
  const { data } = await axios.get<Vehicle[]>(`${API_BASE}/vehicles/`);
  return data;
}

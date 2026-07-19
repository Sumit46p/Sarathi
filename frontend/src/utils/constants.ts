import L from 'leaflet';


export const VEHICLE_TYPES = [
  { value: 'ambulance', label: 'Ambulance' },
  { value: 'logistics', label: 'Logistics' },
  { value: 'municipal', label: 'Municipal' },
] as const;

export const TYPE_COLORS: Record<string, string> = {
  ambulance: '#dc2626',
  logistics: '#2563eb',
  municipal: '#059669',
};

export const TYPE_LABELS: Record<string, string> = {
  ambulance: 'Ambulance',
  logistics: 'Logistics',
  municipal: 'Municipal',
};

export const NEPAL_CENTER: [number, number] = [28.2, 84.0];
export const NEPAL_BOUNDS = L.latLngBounds([26.347, 80.058], [30.447, 88.201]);

export const MAP_OPTIONS = {
  maxBounds: NEPAL_BOUNDS,
  maxBoundsViscosity: 1,
  minZoom: 7,
} as const;

export const NEPAL_BORDER_STYLE: L.PathOptions = {
  color: '#fbbf24',
  weight: 1.5,
  fillColor: '#fef3c7',
  fillOpacity: 0.08,
};

export const POLL_INTERVAL = 4000;

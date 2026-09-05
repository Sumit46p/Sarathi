import L from 'leaflet';


export const VEHICLE_TYPES = [
  { value: 'rental', label: 'Rental Vehicle' },
  { value: 'government', label: 'Government Vehicle' },
  { value: 'company', label: 'Company Vehicle' },
  { value: 'personal', label: 'Personal Vehicle' },
  { value: 'logistics', label: 'Logistics' },
  { value: 'public_transport', label: 'Public Transport' },
  { value: 'commercial', label: 'Commercial / Construction' },
] as const;

export const TYPE_COLORS: Record<string, string> = {
  rental: '#7c3aed',
  government: '#dc2626',
  company: '#2563eb',
  personal: '#d97706',
  logistics: '#0891b2',
  public_transport: '#059669',
  commercial: '#9a3412',
};

export const TYPE_LABELS: Record<string, string> = {
  rental: 'Rental Vehicle',
  government: 'Government Vehicle',
  company: 'Company Vehicle',
  personal: 'Personal Vehicle',
  logistics: 'Logistics',
  public_transport: 'Public Transport',
  commercial: 'Commercial / Construction',
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

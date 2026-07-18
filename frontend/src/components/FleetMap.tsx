import { useEffect, useMemo, useState } from 'react';
import { AlertCircle, MapPinned, Navigation, RefreshCw } from 'lucide-react';
import { CircleMarker, MapContainer, Popup, TileLayer, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { fetchVehicles } from '../api/vehicles';
import type { Vehicle } from '../api/vehicles';

const TYPE_COLORS: Record<Vehicle['vehicle_type'], string> = {
  ambulance: '#dc2626',
  logistics: '#2563eb',
  municipal: '#059669',
};

const TYPE_LABELS: Record<Vehicle['vehicle_type'], string> = {
  ambulance: 'Ambulance',
  logistics: 'Logistics',
  municipal: 'Municipal',
};

const POLL_INTERVAL = 4000;
const NEPAL_CENTER: [number, number] = [28.2, 84.0];
const NEPAL_BOUNDS = L.latLngBounds([26.347, 80.058], [30.447, 88.201]);

function VehicleBounds({ vehicles }: { vehicles: Vehicle[] }) {
  const map = useMap();

  useEffect(() => {
    const points = vehicles
      .filter(vehicle => NEPAL_BOUNDS.contains([vehicle.location.lat, vehicle.location.lng]))
      .map(vehicle => [vehicle.location.lat, vehicle.location.lng] as [number, number]);

    if (points.length > 1) {
      map.fitBounds(L.latLngBounds(points), { padding: [70, 70], maxZoom: 13, animate: true, duration: 0.6 });
    } else if (points.length === 1) {
      map.setView(points[0], 12, { animate: true, duration: 0.6 });
    }
  }, [map, vehicles]);

  return null;
}

export default function FleetMap() {
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      try {
        const data = await fetchVehicles();
        if (active) {
          setVehicles(data);
          setError(null);
          setLastUpdated(new Date());
        }
      } catch (requestError) {
        if (active) setError('Fleet positions could not be refreshed.');
        console.error(requestError);
      } finally {
        if (active) setLoading(false);
      }
    };

    load();
    const timer = window.setInterval(load, POLL_INTERVAL);
    return () => { active = false; window.clearInterval(timer); };
  }, []);

  const nepalVehicles = useMemo(
    () => vehicles.filter(vehicle => NEPAL_BOUNDS.contains([vehicle.location.lat, vehicle.location.lng])),
    [vehicles],
  );

  return (
    <main className="fleet-map-page">
      <header className="fleet-map-header">
        <div className="fleet-map-brand">
          <div className="brand-mark"><Navigation size={18} /></div>
          <div><strong>Sarthi live fleet</strong><span>Nepal operations · {lastUpdated ? `Updated ${lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : 'Connecting'}</span></div>
        </div>
        <div className="fleet-map-legend" aria-label="Vehicle type legend">
          {Object.entries(TYPE_COLORS).map(([type, color]) => (
            <span key={type}><i className="legend-dot" style={{ background: color }} />{TYPE_LABELS[type as Vehicle['vehicle_type']]}</span>
          ))}
          <span className="fleet-map-count"><MapPinned size={13} />{nepalVehicles.length} visible</span>
        </div>
      </header>

      {loading && <div className="map-notice loading" role="status"><RefreshCw className="spin" size={14} />Loading fleet positions</div>}
      {error && <div className="map-notice error" role="alert"><AlertCircle size={14} />{error}</div>}
      {!loading && !error && nepalVehicles.length === 0 && <div className="map-empty-overlay">No vehicle locations are currently reported inside Nepal.</div>}

      <MapContainer
        center={NEPAL_CENTER}
        zoom={7}
        minZoom={7}
        maxBounds={NEPAL_BOUNDS}
        maxBoundsViscosity={1}
        style={{ width: '100%', height: '100%' }}
      >
        <TileLayer
          attribution='&copy; OpenStreetMap &copy; CARTO'
          url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
        />
        <VehicleBounds vehicles={nepalVehicles} />
        {nepalVehicles.map(vehicle => (
          <CircleMarker
            key={vehicle.id}
            center={[vehicle.location.lat, vehicle.location.lng]}
            radius={8}
            pathOptions={{
              color: '#ffffff',
              weight: 2.5,
              fillColor: TYPE_COLORS[vehicle.vehicle_type] ?? '#64748b',
              fillOpacity: vehicle.is_available ? 1 : 0.65,
            }}
          >
            <Popup>
              <div className="map-popup">
                <strong>{vehicle.name}</strong>
                <span>{TYPE_LABELS[vehicle.vehicle_type]}</span>
                <span className={vehicle.is_available ? 'available-text' : 'unavailable-text'}>
                  {vehicle.is_available ? 'Available' : 'In service'}
                </span>
                <span className="mono">{vehicle.location.lat.toFixed(5)}, {vehicle.location.lng.toFixed(5)}</span>
              </div>
            </Popup>
          </CircleMarker>
        ))}
      </MapContainer>
    </main>
  );
}

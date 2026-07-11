import { useEffect, useState } from 'react';
import { MapContainer, TileLayer, CircleMarker, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { fetchVehicles } from '../api/vehicles';
import type { Vehicle } from '../api/vehicles';

/* ── colour palette per vehicle type ── */
const TYPE_COLORS: Record<Vehicle['vehicle_type'], string> = {
  ambulance: '#e74c3c',   // red
  logistics: '#2980b9',   // blue
  municipal: '#27ae60',   // green
};

const TYPE_LABELS: Record<Vehicle['vehicle_type'], string> = {
  ambulance: '🚑 Ambulance',
  logistics: '🚚 Logistics',
  municipal: '🏛️ Municipal',
};

/* ── polling interval (ms) ── */
const POLL_INTERVAL = 4000;

export default function FleetMap() {
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      try {
        const data = await fetchVehicles();
        if (active) {
          setVehicles(data);
          setError(null);
        }
      } catch (err) {
        if (active) setError('Cannot reach API — is Django running?');
        console.error(err);
      }
    };

    load();                                       // fetch on mount
    const timer = setInterval(load, POLL_INTERVAL); // re-fetch every 4s

    return () => {
      active = false;
      clearInterval(timer);
    };
  }, []);

  return (
    <div style={{ width: '100%', height: '100vh', position: 'relative' }}>
      {/* ── header bar ── */}
      <div
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          zIndex: 1000,
          background: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 100%)',
          color: '#fff',
          padding: '12px 24px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          fontFamily: "'Inter', system-ui, sans-serif",
          boxShadow: '0 2px 12px rgba(0,0,0,0.3)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontSize: 22 }}>🚑</span>
          <span style={{ fontSize: 18, fontWeight: 700, letterSpacing: 1 }}>
            Sarthi — Live Fleet Map
          </span>
        </div>

        {/* legend */}
        <div style={{ display: 'flex', gap: 16, fontSize: 13 }}>
          {Object.entries(TYPE_COLORS).map(([type, color]) => (
            <span key={type} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
              <span
                style={{
                  width: 10,
                  height: 10,
                  borderRadius: '50%',
                  background: color,
                  display: 'inline-block',
                }}
              />
              {type}
            </span>
          ))}
          <span style={{ opacity: 0.6 }}>
            {vehicles.length} vehicle{vehicles.length !== 1 ? 's' : ''}
          </span>
        </div>
      </div>

      {/* ── error banner ── */}
      {error && (
        <div
          style={{
            position: 'absolute',
            top: 52,
            left: '50%',
            transform: 'translateX(-50%)',
            zIndex: 1000,
            background: '#e74c3c',
            color: '#fff',
            padding: '8px 20px',
            borderRadius: 6,
            fontSize: 14,
            fontFamily: "'Inter', system-ui, sans-serif",
          }}
        >
          {error}
        </div>
      )}

      {/* ── map ── */}
      <MapContainer
        center={[26.5, 87.9]}
        zoom={12}
        style={{ width: '100%', height: '100%' }}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        {vehicles.map((v) => (
          <CircleMarker
            key={v.id}
            center={[v.location.lat, v.location.lng]}
            radius={10}
            pathOptions={{
              color: '#fff',
              weight: 2,
              fillColor: TYPE_COLORS[v.vehicle_type] ?? '#888',
              fillOpacity: 0.9,
            }}
          >
            <Popup>
              <div style={{ fontFamily: "'Inter', system-ui, sans-serif", minWidth: 140 }}>
                <strong style={{ fontSize: 15 }}>{v.name}</strong>
                <br />
                <span style={{ color: TYPE_COLORS[v.vehicle_type] }}>
                  {TYPE_LABELS[v.vehicle_type] ?? v.vehicle_type}
                </span>
                <br />
                <span
                  style={{
                    color: v.is_available ? '#27ae60' : '#e74c3c',
                    fontWeight: 600,
                  }}
                >
                  {v.is_available ? '✅ Available' : '🚫 Unavailable'}
                </span>
                <br />
                <span style={{ fontSize: 11, color: '#888' }}>
                  {v.location.lat.toFixed(5)}, {v.location.lng.toFixed(5)}
                </span>
              </div>
            </Popup>
          </CircleMarker>
        ))}
      </MapContainer>
    </div>
  );
}

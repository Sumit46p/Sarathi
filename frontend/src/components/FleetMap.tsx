import { useEffect, useState } from 'react';
import { MapContainer, TileLayer, CircleMarker, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { fetchVehicles } from '../api/vehicles';
import type { Vehicle } from '../api/vehicles';

/* ── Muted color palette per vehicle type ── */
const TYPE_COLORS: Record<Vehicle['vehicle_type'], string> = {
  ambulance: '#dc2626',   // muted red
  logistics: '#2563eb',   // muted blue
  municipal: '#059669',   // muted green
};

const TYPE_LABELS: Record<Vehicle['vehicle_type'], string> = {
  ambulance: 'Ambulance',
  logistics: 'Logistics',
  municipal: 'Municipal',
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

    load();
    const timer = setInterval(load, POLL_INTERVAL);

    return () => {
      active = false;
      clearInterval(timer);
    };
  }, []);

  return (
    <div style={{ width: '100%', height: '100vh', position: 'relative' }}>
      {/* Header bar */}
      <div
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          zIndex: 1000,
          background: 'var(--surface)',
          borderBottom: '1px solid var(--surface-border)',
          color: 'var(--text-main)',
          padding: '14px 24px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          fontFamily: 'system-ui, -apple-system, sans-serif',
          boxShadow: '0 1px 3px rgba(0, 0, 0, 0.05)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ fontSize: 20, fontWeight: 700, letterSpacing: 0.5 }}>
            Sarthi Fleet Map
          </span>
        </div>

        {/* Legend */}
        <div style={{ display: 'flex', gap: 20, fontSize: 12.5, fontWeight: 500 }}>
          {Object.entries(TYPE_COLORS).map(([type, color]) => (
            <span key={type} style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'var(--text-secondary)' }}>
              <span
                style={{
                  width: 12,
                  height: 12,
                  borderRadius: '50%',
                  background: color,
                  display: 'inline-block',
                  boxShadow: '0 0 0 2px rgba(255, 255, 255, 0.8)',
                }}
              />
              {TYPE_LABELS[type]}
            </span>
          ))}
          <span style={{ color: 'var(--text-muted)' }}>
            {vehicles.length} {vehicles.length === 1 ? 'vehicle' : 'vehicles'}
          </span>
        </div>
      </div>

      {/* Error banner */}
      {error && (
        <div
          style={{
            position: 'absolute',
            top: 60,
            left: '50%',
            transform: 'translateX(-50%)',
            zIndex: 999,
            background: 'var(--danger)',
            color: '#fff',
            padding: '10px 18px',
            borderRadius: 8,
            fontSize: 13,
            fontWeight: 500,
            animation: 'slideUp 0.25s ease',
          }}
        >
          {error}
        </div>
      )}

      {/* Map */}
      <MapContainer
        center={[26.5, 87.9]}
        zoom={12}
        style={{ width: '100%', height: '100%' }}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>'
          url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
        />

        {vehicles.map((v) => (
          <CircleMarker
            key={v.id}
            center={[v.location.lat, v.location.lng]}
            radius={8}
            pathOptions={{
              color: TYPE_COLORS[v.vehicle_type] ?? '#6b7280',
              weight: 2.5,
              fillColor: TYPE_COLORS[v.vehicle_type] ?? '#6b7280',
              fillOpacity: 0.85,
            }}
          >
            <Popup>
              <div style={{ 
                fontFamily: 'system-ui, -apple-system, sans-serif',
                minWidth: 160,
                padding: '6px 0'
              }}>
                <div style={{ fontWeight: 600, fontSize: 14, marginBottom: 8, color: 'var(--text-main)' }}>
                  {v.name}
                </div>
                <div style={{ fontSize: 12, marginBottom: 6 }}>
                  <div style={{ color: 'var(--text-muted)', marginBottom: 4 }}>Type: <span style={{ color: 'var(--text-secondary)', fontWeight: 500 }}>{TYPE_LABELS[v.vehicle_type]}</span></div>
                  <div style={{ color: 'var(--text-muted)' }}>Status: <span style={{ color: v.is_available ? 'var(--success)' : 'var(--danger)', fontWeight: 500 }}>{v.is_available ? 'Available' : 'Unavailable'}</span></div>
                </div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'monospace', marginTop: 8, paddingTop: 8, borderTop: '1px solid var(--surface-border)' }}>
                  {v.location.lat.toFixed(5)}, {v.location.lng.toFixed(5)}
                </div>
              </div>
            </Popup>
          </CircleMarker>
        ))}
      </MapContainer>
    </div>
  );
}

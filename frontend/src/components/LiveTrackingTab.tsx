import { useState, useEffect, useRef, useCallback } from 'react';
import { api } from '../api/auth';
import type { VehicleLocationUpdate } from '../api/vehicles';
import {
  Car, Truck, Bus, Ambulance, RefreshCw, X, Filter, Radio,
  Gauge, Navigation, User, Phone, Clock, Hash, AlertCircle, ChevronRight,
} from 'lucide-react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

/* --------------------------------------------------------------------------
 * Leaflet icon setup (avoids the broken default icon URL from webpack)
 * -------------------------------------------------------------------------- */
delete (L.Icon.Default.prototype as { _getIconUrl?: unknown })._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl:       'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl:     'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

/* --------------------------------------------------------------------------
 * Vehicle type → colour mapping
 * -------------------------------------------------------------------------- */
const TYPE_COLORS: Record<string, string> = {
  government:       '#1e3a8a',
  logistics:        '#fa8c16',
  public_transport: '#722ed1',
  rental:           '#13c2c2',
  personal:         '#52c41a',
  company:          '#eb2f96',
};
const DEFAULT_COLOR = '#8c8c8c';

const TYPE_LABELS: Record<string, string> = {
  government:       'Government',
  logistics:        'Logistics',
  public_transport: 'Public Transport',
  rental:           'Rental',
  personal:         'Personal',
  company:          'Company',
};

const STATUS_LABELS: Record<string, string> = {
  available:   'Available',
  assigned:    'Assigned',
  reserved:    'Reserved',
  in_use:      'In Use',
  on_route:    'On Route',
  rented:      'Rented',
  maintenance: 'Maintenance',
  offline:     'Offline',
};

/* --------------------------------------------------------------------------
 * Custom coloured divIcon for each vehicle type
 * -------------------------------------------------------------------------- */
function makeVehicleIcon(type: string, isLive: boolean, photoUrl?: string | null) {
  const color = TYPE_COLORS[type] ?? DEFAULT_COLOR;
  const pulseDot = isLive
    ? `<span style="position:absolute;top:-3px;right:-3px;width:9px;height:9px;border-radius:50%;background:#52c41a;border:2px solid #fff;animation:pulse 1.5s infinite;"></span>`
    : '';

  const inner = photoUrl
    ? `<img src="${photoUrl}" alt="" style="width:28px;height:28px;border-radius:50%;object-fit:cover;display:block;" />`
    : `<svg viewBox="0 0 32 32" width="32" height="32">
        <circle cx="16" cy="14" r="12" fill="${color}" stroke="#fff" stroke-width="2"/>
        <polygon points="10,22 22,22 16,32" fill="${color}"/>
        <text x="16" y="19" text-anchor="middle" font-size="12" fill="#fff" font-weight="bold"
          font-family="system-ui,sans-serif">${(type[0] ?? '?').toUpperCase()}</text>
      </svg>`;

  return L.divIcon({
    className: '',
    iconSize: [32, 32],
    iconAnchor: [16, 32],
    popupAnchor: [0, -34],
    html: `<div style="position:relative;width:32px;height:32px;border-radius:50%;border:2px solid ${color};box-shadow:0 2px 6px rgba(0,0,0,.3);overflow:visible;display:flex;align-items:center;justify-content:center;">
      ${inner}
      ${pulseDot}
    </div>`,
  });
}

/* --------------------------------------------------------------------------
 * Sub-component: auto-pan map when a marker moves
 * -------------------------------------------------------------------------- */
function FleetMarkers({
  vehicles,
  liveUpdates,
  selectedId,
  onSelect,
}: {
  vehicles: VehicleRow[];
  liveUpdates: Map<number, VehicleLocationUpdate>;
  selectedId: number | null;
  onSelect: (id: number) => void;
}) {
  const map = useMap();
  const prevPositions = useRef<Map<number, [number, number]>>(new Map());

  useEffect(() => {
    liveUpdates.forEach((upd) => {
      const prev = prevPositions.current.get(upd.vehicle_id);
      if (prev && (prev[0] !== upd.lat || prev[1] !== upd.lng)) {
        if (selectedId === upd.vehicle_id) {
          map.panTo([upd.lat, upd.lng], { animate: true, duration: 0.8 });
        }
      }
      prevPositions.current.set(upd.vehicle_id, [upd.lat, upd.lng]);
    });
  }, [liveUpdates, selectedId, map]);

  return (
    <>
      {vehicles.map((v) => {
        const live = liveUpdates.get(v.id);
        const pos: [number, number] = live ? [live.lat, live.lng] : [v.lat, v.lng];
        if (!pos[0] || !pos[1]) return null;
        const isLive = !!live;
        const speed = live?.speed_kmh;
        return (
          <Marker
            key={v.id}
            position={pos}
            icon={makeVehicleIcon(v.vehicle_type, isLive, v.photo_url)}
            eventHandlers={{ click: () => onSelect(v.id) }}
          >
            <Popup>
              <div style={{ minWidth: 180 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
                  <strong style={{ fontSize: '0.9rem' }}>{live?.vehicle_name ?? v.name}</strong>
                  {isLive && (
                    <span style={{ fontSize: '0.65rem', color: '#52c41a', display: 'flex', alignItems: 'center', gap: 4 }}>
                      <span style={{ width: 7, height: 7, borderRadius: '50%', background: '#52c41a', display: 'inline-block' }} />
                      LIVE
                    </span>
                  )}
                </div>
                <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: '0.75rem' }}>
                  <tbody>
                    <tr><td style={{ color: '#888', paddingRight: 8 }}>Type</td><td>{TYPE_LABELS[live?.vehicle_type ?? v.vehicle_type] ?? v.vehicle_type}</td></tr>
                    <tr><td style={{ color: '#888' }}>Status</td><td>{STATUS_LABELS[live?.vehicle_status ?? v.vehicle_status] ?? v.vehicle_status}</td></tr>
                    {v.number_plate && <tr><td style={{ color: '#888' }}>Plate</td><td>{v.number_plate}</td></tr>}
                    {(live?.driver_name ?? v.driver_name) && <tr><td style={{ color: '#888' }}>Driver</td><td>{live?.driver_name ?? v.driver_name}</td></tr>}
                    {speed != null && <tr><td style={{ color: '#888' }}>Speed</td><td>{speed.toFixed(0)} km/h</td></tr>}
                    {live?.timestamp && <tr><td style={{ color: '#888' }}>Updated</td><td>{new Date(live.timestamp).toLocaleTimeString()}</td></tr>}
                  </tbody>
                </table>
              </div>
            </Popup>
          </Marker>
        );
      })}
    </>
  );
}

/* --------------------------------------------------------------------------
 * REST-snapshot vehicle shape (from /api/vehicles/)
 * -------------------------------------------------------------------------- */
interface VehicleRow {
  id: number;
  name: string;
  vehicle_type: string;
  vehicle_status: string;
  number_plate: string;
  driver_name: string | null;
  photo_url: string | null;
  lat: number;
  lng: number;
  last_location_at: string | null;
  odometer_km: number;
  total_distance_km: number;
}

function toRow(v: Record<string, unknown>): VehicleRow {
  const loc = v.location as { lat?: number; lng?: number; coordinates?: [number, number] } | null;
  // API can return {lat, lng} (from serializer) or GeoJSON-style {coordinates:[lng,lat]}
  const lng = loc?.lng ?? loc?.coordinates?.[0] ?? 0;
  const lat = loc?.lat ?? loc?.coordinates?.[1] ?? 0;
  const driver = v.driver as { name?: string } | null;
  return {
    id:               v.id as number,
    name:             v.name as string,
    vehicle_type:     v.vehicle_type as string,
    vehicle_status:   v.vehicle_status as string,
    number_plate:     (v.number_plate as string) ?? '',
    driver_name:      (v.driver_name as string | null) ?? driver?.name ?? null,
    photo_url:        (v.photo_url as string | null) ?? null,
    lat,
    lng,
    last_location_at: v.last_location_at as string | null,
    odometer_km:      (v.odometer_km as number) ?? 0,
    total_distance_km: (v.total_distance_km as number) ?? 0,
  };
}

/* --------------------------------------------------------------------------
 * Props
 * -------------------------------------------------------------------------- */
interface LiveTrackingTabProps {
  vehicleLocationUpdates?: Map<number, VehicleLocationUpdate>;
}

/* --------------------------------------------------------------------------
 * Main Component
 * -------------------------------------------------------------------------- */
export default function LiveTrackingTab({ vehicleLocationUpdates = new Map() }: LiveTrackingTabProps) {
  const [vehicles, setVehicles] = useState<VehicleRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [search, setSearch] = useState('');
  const [showSidebar, setShowSidebar] = useState(true);
  const mapRef = useRef<L.Map | null>(null);

  /* ---- REST snapshot ---- */
  const fetchVehicles = useCallback(async () => {
    try {
      setLoading(true);
      const resp = await api.get('/vehicles/');
      setVehicles((resp.data as Record<string, unknown>[]).map(toRow));
    } catch {
      // silent – map will still show via WS updates
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchVehicles(); }, [fetchVehicles]);

  /* ---- Merge WS updates into vehicle list for sidebar ---- */
  const mergedVehicles: VehicleRow[] = vehicles.map((v) => {
    const upd = vehicleLocationUpdates.get(v.id);
    if (!upd) return v;
    return {
      ...v,
      lat: upd.lat,
      lng: upd.lng,
      vehicle_status: upd.vehicle_status ?? v.vehicle_status,
      driver_name: upd.driver_name ?? v.driver_name,
    };
  });

  /* ---- Filtering ---- */
  const filtered = mergedVehicles.filter((v) => {
    if (typeFilter !== 'all' && v.vehicle_type !== typeFilter) return false;
    if (statusFilter !== 'all' && v.vehicle_status !== statusFilter) return false;
    if (search && !v.name.toLowerCase().includes(search.toLowerCase()) &&
        !v.number_plate.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const liveCount = vehicleLocationUpdates.size;
  const NEPAL_CENTER: [number, number] = [28.3949, 84.124];

  /* ---- Fly to selected ---- */
  function handleSelectVehicle(id: number) {
    setSelectedId(id);
    const v = mergedVehicles.find(x => x.id === id);
    if (!v) return;
    const live = vehicleLocationUpdates.get(id);
    const pos: [number, number] = live ? [live.lat, live.lng] : [v.lat, v.lng];
    mapRef.current?.flyTo(pos, 16, { animate: true, duration: 1 });
  }

  return (
    <div style={{ display: 'flex', height: 'calc(100vh - 64px)', minHeight: 400, position: 'relative', overflow: 'hidden' }}>

      {/* ── Sidebar ── */}
      {showSidebar && (
        <aside style={{
          width: 300, minWidth: 260, maxWidth: 320, background: 'var(--surface)',
          borderRight: '1px solid var(--border)', display: 'flex', flexDirection: 'column',
          zIndex: 10, overflow: 'hidden',
        }}>
          {/* header */}
          <div style={{ padding: '14px 16px', borderBottom: '1px solid var(--border)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
              <h2 style={{ margin: 0, fontSize: '1rem', fontWeight: 700 }}>Fleet Tracker</h2>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: '0.72rem', color: liveCount > 0 ? 'var(--success)' : 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>
                  <Radio size={11} />
                  {liveCount > 0 ? `${liveCount} live` : 'No live feeds'}
                </span>
                <button className="icon-button" onClick={fetchVehicles} title="Refresh">
                  <RefreshCw size={14} className={loading ? 'spin' : ''} />
                </button>
              </div>
            </div>
            {/* search */}
            <input
              className="input-field"
              style={{ width: '100%', marginBottom: 8 }}
              placeholder="Search name or plate…"
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
            {/* filters */}
            <div style={{ display: 'flex', gap: 6 }}>
              <select className="input-field" style={{ flex: 1, fontSize: '0.75rem' }} value={typeFilter} onChange={e => setTypeFilter(e.target.value)}>
                <option value="all">All types</option>
                {Object.entries(TYPE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
              <select className="input-field" style={{ flex: 1, fontSize: '0.75rem' }} value={statusFilter} onChange={e => setStatusFilter(e.target.value)}>
                <option value="all">All statuses</option>
                {Object.entries(STATUS_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </div>
          </div>

          {/* vehicle list */}
          <ul style={{ flex: 1, overflowY: 'auto', margin: 0, padding: 0, listStyle: 'none' }}>
            {loading && (
              <li style={{ padding: 20, textAlign: 'center', color: 'var(--text-muted)', fontSize: '0.8rem' }}>
                <RefreshCw size={16} className="spin" style={{ display: 'inline', marginRight: 6 }} />Loading…
              </li>
            )}
            {!loading && filtered.length === 0 && (
              <li style={{ padding: 20, textAlign: 'center', color: 'var(--text-muted)', fontSize: '0.8rem' }}>
                No vehicles match
              </li>
            )}
            {filtered.map((v) => {
              const isLive = vehicleLocationUpdates.has(v.id);
              const isSelected = selectedId === v.id;
              const color = TYPE_COLORS[v.vehicle_type] ?? DEFAULT_COLOR;
              const upd = vehicleLocationUpdates.get(v.id);
              return (
                <li
                  key={v.id}
                  onClick={() => handleSelectVehicle(v.id)}
                  style={{
                    padding: '10px 14px',
                    cursor: 'pointer',
                    borderBottom: '1px solid var(--border)',
                    background: isSelected ? 'var(--primary-alpha)' : 'transparent',
                    borderLeft: `3px solid ${isSelected ? color : 'transparent'}`,
                    transition: 'background 0.15s',
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                      {v.photo_url ? (
                        <img
                          src={v.photo_url}
                          alt={v.name}
                          style={{
                            width: 28, height: 28, borderRadius: '50%',
                            objectFit: 'cover', flexShrink: 0,
                            border: `2px solid ${color}`,
                          }}
                        />
                      ) : (
                        <span style={{
                          width: 28, height: 28, borderRadius: '50%',
                          background: color, display: 'flex', alignItems: 'center',
                          justifyContent: 'center', flexShrink: 0, color: '#fff',
                          fontSize: '0.7rem', fontWeight: 700, textTransform: 'uppercase',
                          border: `2px solid ${color}`,
                        }}>
                          {v.vehicle_type[0]}
                        </span>
                      )}
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontWeight: 600, fontSize: '0.82rem', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                          {v.name}
                        </div>
                        <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                          {TYPE_LABELS[v.vehicle_type] ?? v.vehicle_type}
                          {v.number_plate ? ` · ${v.number_plate}` : ''}
                        </div>
                      </div>
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 3, flexShrink: 0, marginLeft: 6 }}>
                      {isLive ? (
                        <span style={{ fontSize: '0.65rem', color: '#52c41a', display: 'flex', alignItems: 'center', gap: 3 }}>
                          <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#52c41a', display: 'inline-block', animation: 'pulse 1.5s infinite' }} />
                          Live
                        </span>
                      ) : (
                        <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)' }}>Idle</span>
                      )}
                      <span style={{
                        fontSize: '0.62rem', padding: '1px 5px', borderRadius: 4,
                        background: `${color}22`, color: color, fontWeight: 600,
                      }}>
                        {STATUS_LABELS[v.vehicle_status] ?? v.vehicle_status}
                      </span>
                    </div>
                  </div>
                  {/* driver / speed row */}
                  {(v.driver_name || upd?.speed_kmh != null) && (
                    <div style={{ marginTop: 5, display: 'flex', gap: 10, fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                      {v.driver_name && <span style={{ display: 'flex', alignItems: 'center', gap: 3 }}><User size={10} />{v.driver_name}</span>}
                      {upd?.speed_kmh != null && <span style={{ display: 'flex', alignItems: 'center', gap: 3 }}><Gauge size={10} />{upd.speed_kmh.toFixed(0)} km/h</span>}
                      {upd?.timestamp && <span style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 3 }}><Clock size={10} />{new Date(upd.timestamp).toLocaleTimeString()}</span>}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>

          {/* legend */}
          <div style={{ padding: '10px 14px', borderTop: '1px solid var(--border)', display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {Object.entries(TYPE_COLORS).map(([type, color]) => (
              <span key={type} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.65rem', color: 'var(--text-muted)' }}>
                <span style={{ width: 10, height: 10, borderRadius: '50%', background: color, display: 'inline-block' }} />
                {TYPE_LABELS[type]}
              </span>
            ))}
          </div>
        </aside>
      )}

      {/* ── Sidebar toggle ── */}
      <button
        onClick={() => setShowSidebar(s => !s)}
        style={{
          position: 'absolute', left: showSidebar ? 302 : 0, top: '50%', transform: 'translateY(-50%)',
          zIndex: 20, background: 'var(--surface)', border: '1px solid var(--border)',
          borderLeft: showSidebar ? undefined : 'none',
          borderRadius: showSidebar ? '0 6px 6px 0' : '0 6px 6px 0',
          padding: '8px 4px', cursor: 'pointer', transition: 'left 0.2s',
        }}
        title={showSidebar ? 'Hide panel' : 'Show panel'}
      >
        <ChevronRight size={14} style={{ transform: showSidebar ? 'rotate(180deg)' : undefined, transition: 'transform 0.2s' }} />
      </button>

      {/* ── Map ── */}
      <div style={{ flex: 1, position: 'relative' }}>
        {/* live ping counter overlay */}
        {liveCount > 0 && (
          <div style={{
            position: 'absolute', top: 12, right: 12, zIndex: 999,
            background: 'rgba(0,0,0,0.7)', color: '#52c41a', borderRadius: 20,
            padding: '5px 12px', fontSize: '0.75rem', display: 'flex', alignItems: 'center', gap: 6,
            backdropFilter: 'blur(6px)', border: '1px solid rgba(82,196,26,0.4)',
          }}>
            <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#52c41a', display: 'inline-block', animation: 'pulse 1.5s infinite' }} />
            {liveCount} vehicle{liveCount > 1 ? 's' : ''} broadcasting live GPS
          </div>
        )}

        <MapContainer
          center={NEPAL_CENTER}
          zoom={7}
          style={{ width: '100%', height: '100%' }}
          ref={mapRef}
        >
          <TileLayer
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            attribution='&copy; OpenStreetMap contributors'
          />
          <FleetMarkers
            vehicles={filtered}
            liveUpdates={vehicleLocationUpdates}
            selectedId={selectedId}
            onSelect={handleSelectVehicle}
          />
        </MapContainer>
      </div>
    </div>
  );
}

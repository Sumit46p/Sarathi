import { useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle, Car, MapPin, Navigation, RefreshCw, Search, SlidersHorizontal, X,
} from 'lucide-react';
import {
  CircleMarker, GeoJSON, MapContainer, Marker, Popup, TileLayer, useMap,
} from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { fetchVehicles } from '../api/vehicles';
import type { Vehicle } from '../api/vehicles';
import NEPAL_GEOJSON from '../data/nepalBorder';

/* ─────────────────────────── constants ─────────────────────────── */

const POLL_INTERVAL = 5000;
const NEPAL_CENTER: [number, number] = [28.2, 84.0];
const NEPAL_BOUNDS = L.latLngBounds([26.347, 80.058], [30.447, 88.201]);

const BORDER_STYLE: L.PathOptions = {
  color: '#fbbf24', weight: 1.5, fillColor: '#fef3c7', fillOpacity: 0.08,
};

const TYPE_COLORS: Record<Vehicle['vehicle_type'], string> = {
  rental: '#7c3aed',
  government: '#dc2626',
  company: '#2563eb',
  personal: '#d97706',
  logistics: '#0891b2',
  public_transport: '#059669',
  commercial: '#9a3412',
};

const TYPE_LABELS: Record<Vehicle['vehicle_type'], string> = {
  rental: 'Rental',
  government: 'Government',
  company: 'Company',
  personal: 'Personal',
  logistics: 'Logistics',
  public_transport: 'Public Transport',
  commercial: 'Commercial',
};

const FUEL_LABELS: Record<string, string> = {
  petrol: '⛽ Petrol', diesel: '🛢 Diesel', ev: '⚡ EV',
};

/* ─────────────────────────── helpers ─────────────────────────── */

function createPhotoIcon(photoUrl: string, borderColor: string) {
  return L.divIcon({
    className: '',
    html: `<div style="width:28px;height:28px;border-radius:50%;border:2px solid ${borderColor};overflow:hidden;box-shadow:0 2px 6px rgba(0,0,0,0.4);"><img src="${photoUrl}" style="width:100%;height:100%;object-fit:cover;" /></div>`,
    iconSize: [28, 28], iconAnchor: [14, 14], popupAnchor: [0, -16],
  });
}

function createPulseIcon(color: string) {
  return L.divIcon({
    className: '',
    html: `<div style="position:relative;width:22px;height:22px;"><span style="position:absolute;inset:0;border-radius:50%;background:${color};opacity:.35;animation:lt-pulse 1.6s ease-out infinite;"></span><span style="position:absolute;inset:4px;border-radius:50%;background:${color};box-shadow:0 0 0 2px #fff;"></span></div>`,
    iconSize: [22, 22], iconAnchor: [11, 11], popupAnchor: [0, -14],
  });
}

/* ─────────────────────────── FocusFly – flies map to vehicle ─────────────────────────── */

function FocusFly({ target }: { target: { lat: number; lng: number } | null }) {
  const map = useMap();
  useEffect(() => {
    if (target) map.flyTo([target.lat, target.lng], 15, { animate: true, duration: 0.8 });
  }, [map, target]);
  return null;
}

/* ─────────────────────────── main component ─────────────────────────── */

export default function LiveTracking() {
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);

  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('all');

  const [focusTarget, setFocusTarget] = useState<{ lat: number; lng: number } | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(null);

  const searchRef = useRef<HTMLInputElement>(null);

  /* polling */
  useEffect(() => {
    let active = true;
    const load = async () => {
      try {
        const data = await fetchVehicles();
        if (active) { setVehicles(data); setError(null); setLastUpdated(new Date()); }
      } catch { if (active) setError('Could not refresh fleet positions.'); }
      finally { if (active) setLoading(false); }
    };
    load();
    const t = window.setInterval(load, POLL_INTERVAL);
    return () => { active = false; clearInterval(t); };
  }, []);

  /* filtered list in sidebar */
  const sidebarList = useMemo(() => {
    return vehicles.filter(v => {
      const q = search.toLowerCase();
      const nameMatch = v.name.toLowerCase().includes(q) || (v.number_plate ?? '').toLowerCase().includes(q);
      const typeMatch = typeFilter === 'all' || v.vehicle_type === typeFilter;
      const statusMatch = statusFilter === 'all'
        || (statusFilter === 'available' && v.is_available)
        || (statusFilter === 'unavailable' && !v.is_available);
      return nameMatch && typeMatch && statusMatch;
    });
  }, [vehicles, search, typeFilter, statusFilter]);

  /* vehicles shown on map */
  const mapVehicles = useMemo(
    () => vehicles.filter(v => v.location && NEPAL_BOUNDS.contains([v.location.lat, v.location.lng])),
    [vehicles],
  );

  const handleSelect = (v: Vehicle) => {
    setSelectedId(v.id);
    if (v.location) setFocusTarget({ lat: v.location.lat, lng: v.location.lng });
  };

  const clearSearch = () => { setSearch(''); searchRef.current?.focus(); };

  return (
    <div className="lt-layout">
      {/* ── sidebar ── */}
      <aside className="lt-sidebar">
        {/* header */}
        <div className="lt-sidebar-header">
          <div className="lt-sidebar-title">
            <Navigation size={16} />
            <strong>Live Tracking</strong>
          </div>
          {lastUpdated && (
            <span className="lt-updated">
              Updated {lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
            </span>
          )}
        </div>

        {/* search */}
        <div className="lt-search-wrap">
          <Search size={14} className="lt-search-icon" />
          <input
            ref={searchRef}
            className="lt-search"
            placeholder="Search vehicle or plate…"
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
          {search && (
            <button className="lt-search-clear" onClick={clearSearch} aria-label="Clear">
              <X size={13} />
            </button>
          )}
        </div>

        {/* filters */}
        <div className="lt-filters">
          <SlidersHorizontal size={13} />
          <select
            className="lt-filter-select"
            value={typeFilter}
            onChange={e => setTypeFilter(e.target.value)}
            aria-label="Filter by vehicle type"
          >
            <option value="all">All types</option>
            {Object.entries(TYPE_LABELS).map(([val, label]) => (
              <option key={val} value={val}>{label}</option>
            ))}
          </select>
          <select
            className="lt-filter-select"
            value={statusFilter}
            onChange={e => setStatusFilter(e.target.value)}
            aria-label="Filter by status"
          >
            <option value="all">All status</option>
            <option value="available">Available</option>
            <option value="unavailable">In service</option>
          </select>
        </div>

        {/* stats row */}
        <div className="lt-stats">
          <span><span className="lt-stat-val">{vehicles.length}</span> total</span>
          <span><span className="lt-stat-val" style={{ color: '#22c55e' }}>{vehicles.filter(v => v.is_available).length}</span> available</span>
          <span><span className="lt-stat-val" style={{ color: '#f59e0b' }}>{vehicles.filter(v => !v.is_available).length}</span> in service</span>
        </div>

        {/* vehicle list */}
        <div className="lt-vehicle-list" role="list" aria-label="Vehicle list">
          {loading && (
            <div className="lt-list-notice">
              <RefreshCw size={14} className="spin" /> Loading vehicles…
            </div>
          )}
          {!loading && error && (
            <div className="lt-list-notice error">
              <AlertCircle size={14} /> {error}
            </div>
          )}
          {!loading && !error && sidebarList.length === 0 && (
            <div className="lt-list-notice">No vehicles match your filters.</div>
          )}
          {sidebarList.map(v => {
            const color = TYPE_COLORS[v.vehicle_type] ?? '#64748b';
            const isSelected = v.id === selectedId;
            return (
              <button
                key={v.id}
                className={`lt-vehicle-card ${isSelected ? 'selected' : ''}`}
                onClick={() => handleSelect(v)}
                role="listitem"
                aria-pressed={isSelected}
              >
                <div className="lt-card-photo">
                  {v.photo_url
                    ? <img src={v.photo_url} alt={v.name} />
                    : <span className="lt-card-photo-fallback" style={{ background: color }}><Car size={16} /></span>}
                </div>
                <div className="lt-card-info">
                  <span className="lt-card-name">{v.name}</span>
                  <span className="lt-card-meta">
                    <i className="lt-dot" style={{ background: color }} />
                    {TYPE_LABELS[v.vehicle_type]}
                    {v.fuel_type && <> · {FUEL_LABELS[v.fuel_type] ?? v.fuel_type}</>}
                  </span>
                  {v.number_plate && <span className="lt-card-plate">{v.number_plate}</span>}
                </div>
                <div className="lt-card-status-col">
                  <span className={`lt-card-status ${v.is_available ? 'available' : 'unavailable'}`}>
                    {v.is_available ? 'Available' : 'In service'}
                  </span>
                  {v.location && (
                    <span className="lt-card-locate">
                      <MapPin size={11} /> Locate
                    </span>
                  )}
                </div>
              </button>
            );
          })}
        </div>
      </aside>

      {/* ── map ── */}
      <div className="lt-map-wrap">
        {/* type legend */}
        <div className="lt-legend">
          {Object.entries(TYPE_COLORS).map(([type, color]) => (
            <span key={type}>
              <i className="lt-dot" style={{ background: color }} />
              {TYPE_LABELS[type as Vehicle['vehicle_type']]}
            </span>
          ))}
        </div>

        {!loading && !error && mapVehicles.length === 0 && (
          <div className="lt-map-empty">No vehicles with GPS positions in Nepal.</div>
        )}

        <MapContainer
          center={NEPAL_CENTER}
          zoom={7}
          minZoom={6}
          maxBounds={NEPAL_BOUNDS}
          maxBoundsViscosity={0.8}
          style={{ width: '100%', height: '100%' }}
        >
          <TileLayer
            attribution='&copy; <a href="https://www.esri.com">Esri</a>'
            url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
          />
          <GeoJSON data={NEPAL_GEOJSON as GeoJSON.GeoJsonObject} style={() => BORDER_STYLE} />
          <FocusFly target={focusTarget} />

          {mapVehicles.map(v => {
            const color = TYPE_COLORS[v.vehicle_type] ?? '#64748b';
            const isSelected = v.id === selectedId;
            const pos: [number, number] = [v.location.lat, v.location.lng];
            const icon = v.photo_url
              ? createPhotoIcon(v.photo_url, color)
              : createPulseIcon(isSelected ? '#fff' : color);

            return (
              <Marker key={v.id} position={pos} icon={icon} eventHandlers={{ click: () => handleSelect(v) }}>
                <Popup>
                  <div className="map-popup">
                    {v.photo_url && (
                      <img src={v.photo_url} alt={v.name} style={{ width: 80, height: 56, objectFit: 'cover', borderRadius: 6, marginBottom: 6 }} />
                    )}
                    <strong>{v.name}</strong>
                    <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                      <i className="lt-dot" style={{ background: color, flexShrink: 0 }} />
                      {TYPE_LABELS[v.vehicle_type]}
                    </span>
                    {v.number_plate && <span className="mono">{v.number_plate}</span>}
                    {v.fuel_type && <span>{FUEL_LABELS[v.fuel_type] ?? v.fuel_type}</span>}
                    <span className={v.is_available ? 'available-text' : 'unavailable-text'}>
                      {v.is_available ? '● Available' : '● In service'}
                    </span>
                    <span className="mono" style={{ fontSize: '0.7rem' }}>
                      {v.location.lat.toFixed(5)}, {v.location.lng.toFixed(5)}
                    </span>
                  </div>
                </Popup>
              </Marker>
            );
          })}

          {/* highlighted selected ring */}
          {selectedId && (() => {
            const sv = mapVehicles.find(v => v.id === selectedId);
            if (!sv) return null;
            return (
              <CircleMarker
                center={[sv.location.lat, sv.location.lng]}
                radius={22}
                pathOptions={{ color: '#fff', weight: 2.5, fillOpacity: 0, opacity: 0.85 }}
              />
            );
          })()}
        </MapContainer>
      </div>
    </div>
  );
}

import { useState, useEffect, useCallback } from 'react';
import { api } from '../api/auth';
import {
  Plus, Edit2, Trash2, Map, RefreshCw, X, Save, AlertCircle,
  MapPin, ChevronDown, ChevronUp, Check, ToggleLeft, ToggleRight,
  Navigation, Layers, MoveVertical, Car,
} from 'lucide-react';
import { toast } from '../components/toast';

/* --------------------------------------------------------------------------
 * Types
 * -------------------------------------------------------------------------- */
interface RouteStop {
  id: number;
  order: number;
  name: string;
  lat: number;
  lng: number;
}

interface Route {
  id: number;
  name: string;
  description: string;
  start_name: string;
  start_lat: number;
  start_lng: number;
  end_name: string;
  end_lat: number;
  end_lng: number;
  expected_distance_km: number | null;
  expected_duration_min: number | null;
  is_active: boolean;
  stops: RouteStop[];
  vehicle_count: number;
  assigned_vehicles?: Array<{
    id: number;
    name: string;
    number_plate: string | null;
    vehicle_status: string;
  }>;
}

interface RouteForm {
  name: string;
  description: string;
  start_name: string;
  start_lat: string;
  start_lng: string;
  end_name: string;
  end_lat: string;
  end_lng: string;
  expected_distance_km: string;
  expected_duration_min: string;
  is_active: boolean;
}

interface StopForm {
  name: string;
  lat: string;
  lng: string;
}

const EMPTY_FORM: RouteForm = {
  name: '', description: '',
  start_name: '', start_lat: '', start_lng: '',
  end_name: '', end_lat: '', end_lng: '',
  expected_distance_km: '', expected_duration_min: '',
  is_active: true,
};

const EMPTY_STOP: StopForm = { name: '', lat: '', lng: '' };

/* --------------------------------------------------------------------------
 * Helpers
 * -------------------------------------------------------------------------- */
function fmtDuration(min: number | null): string {
  if (min == null) return '—';
  const h = Math.floor(min / 60);
  const m = Math.round(min % 60);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

/* --------------------------------------------------------------------------
 * Main Component
 * -------------------------------------------------------------------------- */
export default function RoutesTab() {
  const [routes, setRoutes] = useState<Route[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Modal state
  const [showModal, setShowModal] = useState(false);
  const [editRoute, setEditRoute] = useState<Route | null>(null);
  const [form, setForm] = useState<RouteForm>(EMPTY_FORM);

  // Expanded stops panel
  const [expandedRouteId, setExpandedRouteId] = useState<number | null>(null);

  // Add-stop form per route
  const [addStopRouteId, setAddStopRouteId] = useState<number | null>(null);
  const [stopForm, setStopForm] = useState<StopForm>(EMPTY_STOP);
  const [savingStop, setSavingStop] = useState(false);

  /* ---------------------------------------------------------------------- */
  const fetchRoutes = useCallback(async () => {
    try {
      setLoading(true);
      const response = await api.get('/routes/');
      setRoutes(response.data);
    } catch {
      toast.error('Failed to load routes');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchRoutes(); }, [fetchRoutes]);

  /* ---------------------------------------------------------------------- */
  function openCreate() {
    setEditRoute(null);
    setForm(EMPTY_FORM);
    setError(null);
    setShowModal(true);
  }

  function openEdit(route: Route) {
    setEditRoute(route);
    setForm({
      name: route.name,
      description: route.description,
      start_name: route.start_name,
      start_lat: String(route.start_lat),
      start_lng: String(route.start_lng),
      end_name: route.end_name,
      end_lat: String(route.end_lat),
      end_lng: String(route.end_lng),
      expected_distance_km: route.expected_distance_km != null ? String(route.expected_distance_km) : '',
      expected_duration_min: route.expected_duration_min != null ? String(route.expected_duration_min) : '',
      is_active: route.is_active,
    });
    setError(null);
    setShowModal(true);
  }

  function closeModal() {
    setShowModal(false);
    setEditRoute(null);
    setError(null);
  }

  /* ---------------------------------------------------------------------- */
  async function handleSave() {
    if (!form.name.trim()) { setError('Route name is required.'); return; }
    if (!form.start_name.trim()) { setError('Start location name is required.'); return; }
    if (!form.end_name.trim()) { setError('End location name is required.'); return; }
    if (!form.start_lat || !form.start_lng) { setError('Start coordinates are required.'); return; }
    if (!form.end_lat || !form.end_lng) { setError('End coordinates are required.'); return; }

    const payload = {
      name: form.name.trim(),
      description: form.description.trim(),
      start_name: form.start_name.trim(),
      start_lat: parseFloat(form.start_lat),
      start_lng: parseFloat(form.start_lng),
      end_name: form.end_name.trim(),
      end_lat: parseFloat(form.end_lat),
      end_lng: parseFloat(form.end_lng),
      expected_distance_km: form.expected_distance_km ? parseFloat(form.expected_distance_km) : null,
      expected_duration_min: form.expected_duration_min ? parseFloat(form.expected_duration_min) : null,
      is_active: form.is_active,
    };

    try {
      setSaving(true);
      setError(null);
      if (editRoute) {
        await api.patch(`/routes/${editRoute.id}/`, payload);
        toast.success('Route updated');
      } else {
        await api.post('/routes/', payload);
        toast.success('Route created');
      }
      closeModal();
      await fetchRoutes();
    } catch (err) {
      const e = err as any;
      const data = e.response?.data;
      const msg = data ? Object.values(data).flat()[0] : null;
      setError(typeof msg === 'string' ? msg : 'Failed to save route.');
    } finally {
      setSaving(false);
    }
  }

  /* ---------------------------------------------------------------------- */
  async function handleDelete(route: Route) {
    if (!window.confirm(`Deactivate route "${route.name}"? This sets the route to inactive.`)) return;
    try {
      await api.delete(`/routes/${route.id}/`);
      toast.success('Route deactivated');
      await fetchRoutes();
    } catch {
      toast.error('Failed to deactivate route');
    }
  }

  async function handleToggleActive(route: Route) {
    try {
      await api.patch(`/routes/${route.id}/`, { is_active: !route.is_active });
      toast.success(route.is_active ? 'Route deactivated' : 'Route activated');
      await fetchRoutes();
    } catch {
      toast.error('Failed to update route status');
    }
  }

  /* ---------------------------------------------------------------------- */
  async function handleAddStop(routeId: number) {
    if (!stopForm.name.trim()) { toast.error('Stop name is required'); return; }
    if (!stopForm.lat || !stopForm.lng) { toast.error('Latitude and longitude are required'); return; }
    try {
      setSavingStop(true);
      await api.post(`/routes/${routeId}/stops/`, {
        name: stopForm.name.trim(),
        lat: parseFloat(stopForm.lat),
        lng: parseFloat(stopForm.lng),
      });
      toast.success('Stop added');
      setStopForm(EMPTY_STOP);
      setAddStopRouteId(null);
      await fetchRoutes();
    } catch {
      toast.error('Failed to add stop');
    } finally {
      setSavingStop(false);
    }
  }

  async function handleDeleteStop(routeId: number, stopId: number) {
    if (!window.confirm('Remove this stop?')) return;
    try {
      await api.delete(`/routes/${routeId}/stops/${stopId}/`);
      toast.success('Stop removed');
      await fetchRoutes();
    } catch {
      toast.error('Failed to remove stop');
    }
  }

  /* ---------------------------------------------------------------------- */
  if (loading) return (
    <div style={{ padding: 60, textAlign: 'center', color: 'var(--text-muted)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
      <RefreshCw className="spin" size={24} />
      <span>Loading routes…</span>
    </div>
  );

  return (
    <div className="tab-content" style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      {/* ── Header ── */}
      <div className="section-toolbar">
        <div>
          <h2 style={{ margin: 0 }}>Route Management</h2>
          <span>{routes.length} route{routes.length !== 1 ? 's' : ''} configured</span>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="button button-secondary" onClick={fetchRoutes}>
            <RefreshCw size={15} /> Refresh
          </button>
          <button id="create-route-btn" className="button button-primary" onClick={openCreate}>
            <Plus size={16} /> New Route
          </button>
        </div>
      </div>

      {/* ── Summary cards ── */}
      <div className="metrics-grid" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
        <article className="metric-card">
          <div className="metric-heading"><span>Total Routes</span><Map size={17} /></div>
          <strong>{routes.length}</strong>
          <p>All configured routes</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Active</span><Navigation size={17} /></div>
          <strong>{routes.filter(r => r.is_active).length}</strong>
          <p>Currently in service</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Total Stops</span><Layers size={17} /></div>
          <strong>{routes.reduce((acc, r) => acc + r.stops.length, 0)}</strong>
          <p>Across all routes</p>
        </article>
      </div>

      {/* ── Table ── */}
      {routes.length === 0 ? (
        <div className="empty-state">
          <div className="empty-icon"><Map size={28} /></div>
          <h3>No Routes Found</h3>
          <p>Create fixed routes for public transport or logistics vehicles.</p>
          <button className="button button-primary" onClick={openCreate}><Plus size={15} /> Create First Route</button>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {routes.map(route => (
            <div
              key={route.id}
              className="metric-card"
              style={{
                padding: 0,
                overflow: 'hidden',
                opacity: route.is_active ? 1 : 0.65,
                transition: 'opacity 0.2s',
              }}
            >
              {/* Route row */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '16px 20px' }}>
                {/* Status pill */}
                <span
                  className={`status-badge ${route.is_active ? 'available' : 'unavailable'}`}
                  style={{ flexShrink: 0 }}
                >
                  <span />
                  {route.is_active ? 'Active' : 'Inactive'}
                </span>

                {/* Route info */}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    <strong style={{ fontSize: '0.95rem' }}>{route.name}</strong>
                    {route.description && (
                      <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)' }}>— {route.description}</span>
                    )}
                  </div>
                  <div style={{ display: 'flex', gap: 16, marginTop: 4, flexWrap: 'wrap' }}>
                    <span className="mono" style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                      <MapPin size={11} style={{ display: 'inline', marginRight: 3, verticalAlign: 'middle' }} />
                      {route.start_name} → {route.end_name}
                    </span>
                    {route.expected_distance_km != null && (
                      <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)' }}>
                        {route.expected_distance_km.toFixed(1)} km
                      </span>
                    )}
                    {route.expected_duration_min != null && (
                      <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)' }}>
                        ~{fmtDuration(route.expected_duration_min)}
                      </span>
                    )}
                    <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)' }}>
                      {route.stops.length} stop{route.stops.length !== 1 ? 's' : ''}
                    </span>
                    {route.vehicle_count > 0 && (
                      <span style={{ fontSize: '0.78rem', color: 'var(--accent)' }}>
                        {route.vehicle_count} vehicle{route.vehicle_count !== 1 ? 's' : ''} on route
                      </span>
                    )}
                  </div>
                </div>

                {/* Actions */}
                <div className="row-actions" style={{ flexShrink: 0 }}>
                  <button
                    className="icon-button"
                    title={route.is_active ? 'Deactivate' : 'Activate'}
                    onClick={() => handleToggleActive(route)}
                  >
                    {route.is_active
                      ? <ToggleRight size={18} style={{ color: 'var(--success)' }} />
                      : <ToggleLeft size={18} style={{ color: 'var(--text-muted)' }} />
                    }
                  </button>
                  <button
                    className="icon-button"
                    title="Expand stops"
                    onClick={() => setExpandedRouteId(expandedRouteId === route.id ? null : route.id)}
                  >
                    {expandedRouteId === route.id ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                  </button>
                  <button className="icon-button" title="Edit route" onClick={() => openEdit(route)}>
                    <Edit2 size={15} />
                  </button>
                  <button
                    className="icon-button"
                    title="Deactivate route"
                    style={{ color: 'var(--danger)' }}
                    onClick={() => handleDelete(route)}
                  >
                    <Trash2 size={15} />
                  </button>
                </div>
              </div>

              {/* Expanded stops panel */}
              {expandedRouteId === route.id && (
                <div style={{
                  borderTop: '1px solid var(--border)',
                  background: 'var(--surface)',
                  padding: '16px 20px',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 12,
                }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <strong style={{ fontSize: '0.85rem' }}>
                      <MoveVertical size={13} style={{ display: 'inline', marginRight: 4, verticalAlign: 'middle' }} />
                      Route Stops ({route.stops.length})
                    </strong>
                    <button
                      className="button button-secondary"
                      style={{ fontSize: '0.75rem', padding: '4px 10px', minHeight: 28 }}
                      onClick={() => {
                        setAddStopRouteId(addStopRouteId === route.id ? null : route.id);
                        setStopForm(EMPTY_STOP);
                      }}
                    >
                      <Plus size={13} /> Add Stop
                    </button>
                  </div>

                  {/* Stops list */}
                  {route.stops.length === 0 ? (
                    <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', margin: 0 }}>
                      No stops defined yet. Click "Add Stop" to add waypoints.
                    </p>
                  ) : (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      {/* Start point */}
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 10px', borderRadius: 6, background: 'var(--surface-hover)', fontSize: '0.82rem' }}>
                        <span style={{ width: 22, height: 22, borderRadius: '50%', background: 'var(--success)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: '0.7rem', flexShrink: 0 }}>S</span>
                        <span style={{ flex: 1 }}><strong>{route.start_name}</strong></span>
                        <span className="mono" style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>{route.start_lat.toFixed(4)}, {route.start_lng.toFixed(4)}</span>
                      </div>
                      {[...route.stops].sort((a, b) => a.order - b.order).map((stop, idx) => (
                        <div key={stop.id} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 10px', borderRadius: 6, background: 'var(--surface-hover)', fontSize: '0.82rem' }}>
                          <span style={{ width: 22, height: 22, borderRadius: '50%', background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: '0.7rem', flexShrink: 0 }}>{idx + 1}</span>
                          <span style={{ flex: 1 }}>{stop.name}</span>
                          <span className="mono" style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>{stop.lat.toFixed(4)}, {stop.lng.toFixed(4)}</span>
                          <button
                            className="icon-button"
                            style={{ color: 'var(--danger)', padding: '2px' }}
                            onClick={() => handleDeleteStop(route.id, stop.id)}
                            title="Remove stop"
                          >
                            <X size={13} />
                          </button>
                        </div>
                      ))}
                      {/* End point */}
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 10px', borderRadius: 6, background: 'var(--surface-hover)', fontSize: '0.82rem' }}>
                        <span style={{ width: 22, height: 22, borderRadius: '50%', background: 'var(--danger)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: '0.7rem', flexShrink: 0 }}>E</span>
                        <span style={{ flex: 1 }}><strong>{route.end_name}</strong></span>
                        <span className="mono" style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>{route.end_lat.toFixed(4)}, {route.end_lng.toFixed(4)}</span>
                      </div>
                    </div>
                  )}

                  {/* Add stop inline form */}
                  {addStopRouteId === route.id && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '12px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg)' }}>
                      <strong style={{ fontSize: '0.82rem' }}>Add New Stop</strong>
                      <div className="form-grid" style={{ gridTemplateColumns: '1fr 1fr 1fr' }}>
                        <div className="form-group" style={{ margin: 0 }}>
                          <label style={{ fontSize: '0.78rem' }}>Stop Name</label>
                          <input className="input-field" value={stopForm.name} onChange={e => setStopForm({ ...stopForm, name: e.target.value })} placeholder="e.g. Koteshwor" />
                        </div>
                        <div className="form-group" style={{ margin: 0 }}>
                          <label style={{ fontSize: '0.78rem' }}>Latitude</label>
                          <input className="input-field" type="number" step="any" value={stopForm.lat} onChange={e => setStopForm({ ...stopForm, lat: e.target.value })} placeholder="27.6900" />
                        </div>
                        <div className="form-group" style={{ margin: 0 }}>
                          <label style={{ fontSize: '0.78rem' }}>Longitude</label>
                          <input className="input-field" type="number" step="any" value={stopForm.lng} onChange={e => setStopForm({ ...stopForm, lng: e.target.value })} placeholder="85.3400" />
                        </div>
                      </div>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button className="button button-primary" style={{ fontSize: '0.78rem', padding: '5px 12px', minHeight: 30 }} onClick={() => handleAddStop(route.id)} disabled={savingStop}>
                          {savingStop ? <RefreshCw size={13} className="spin" /> : <Check size={13} />} Add Stop
                        </button>
                        <button className="button button-secondary" style={{ fontSize: '0.78rem', padding: '5px 12px', minHeight: 30 }} onClick={() => setAddStopRouteId(null)}>
                          Cancel
                        </button>
                      </div>
                    </div>
                  )}
                  {/* Assigned vehicles list */}
                  <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12, marginTop: 4 }}>
                    <strong style={{ fontSize: '0.85rem', display: 'block', marginBottom: 8 }}>
                      <Car size={13} style={{ display: 'inline', marginRight: 4, verticalAlign: 'middle', color: 'var(--accent)' }} />
                      Assigned Vehicles ({route.assigned_vehicles?.length || 0})
                    </strong>
                    {!route.assigned_vehicles || route.assigned_vehicles.length === 0 ? (
                      <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', margin: 0 }}>
                        No vehicles currently active on this route.
                      </p>
                    ) : (
                      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                        {route.assigned_vehicles.map(v => (
                          <div
                            key={v.id}
                            style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: 6,
                              padding: '4px 10px',
                              borderRadius: 16,
                              background: 'var(--surface-hover)',
                              border: '1px solid var(--border)',
                              fontSize: '0.78rem',
                            }}
                          >
                            <span
                              className="status-badge-dot"
                              style={{
                                width: 6,
                                height: 6,
                                borderRadius: '50%',
                                background: v.vehicle_status === 'on_route' ? 'var(--success)' : 'var(--text-muted)',
                              }}
                            />
                            <strong>{v.name}</strong>
                            {v.number_plate && <span style={{ color: 'var(--text-muted)' }}>({v.number_plate})</span>}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* ── Create / Edit Modal ── */}
      {showModal && (
        <div className="modal-overlay" role="presentation" onMouseDown={e => { if (e.target === e.currentTarget) closeModal(); }}>
          <div className="modal-content" role="dialog" aria-modal="true" aria-labelledby="route-modal-title" style={{ maxWidth: 620 }}>
            <div className="modal-header">
              <div>
                <span>Route Management</span>
                <h2 id="route-modal-title">{editRoute ? 'Edit Route' : 'Create New Route'}</h2>
              </div>
              <button className="icon-button" onClick={closeModal} aria-label="Close"><X size={17} /></button>
            </div>
            <div className="modal-body">
              {/* Basic info */}
              <div className="form-group">
                <label htmlFor="route-name">Route Name *</label>
                <input id="route-name" className="input-field" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Kathmandu – Bhaktapur Express" autoFocus />
              </div>
              <div className="form-group">
                <label htmlFor="route-desc">Description</label>
                <input id="route-desc" className="input-field" value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Optional description" />
              </div>

              {/* Start */}
              <p style={{ fontWeight: 600, fontSize: '0.85rem', margin: '12px 0 6px', color: 'var(--text-muted)' }}>Start Location</p>
              <div className="form-grid">
                <div className="form-group">
                  <label htmlFor="start-name">Location Name *</label>
                  <input id="start-name" className="input-field" value={form.start_name} onChange={e => setForm({ ...form, start_name: e.target.value })} placeholder="Ratna Park" />
                </div>
                <div className="form-group">
                  <label htmlFor="start-lat">Latitude *</label>
                  <input id="start-lat" className="input-field" type="number" step="any" value={form.start_lat} onChange={e => setForm({ ...form, start_lat: e.target.value })} placeholder="27.7006" />
                </div>
                <div className="form-group">
                  <label htmlFor="start-lng">Longitude *</label>
                  <input id="start-lng" className="input-field" type="number" step="any" value={form.start_lng} onChange={e => setForm({ ...form, start_lng: e.target.value })} placeholder="85.3163" />
                </div>
              </div>

              {/* End */}
              <p style={{ fontWeight: 600, fontSize: '0.85rem', margin: '12px 0 6px', color: 'var(--text-muted)' }}>End / Destination</p>
              <div className="form-grid">
                <div className="form-group">
                  <label htmlFor="end-name">Location Name *</label>
                  <input id="end-name" className="input-field" value={form.end_name} onChange={e => setForm({ ...form, end_name: e.target.value })} placeholder="Bhaktapur Durbar Square" />
                </div>
                <div className="form-group">
                  <label htmlFor="end-lat">Latitude *</label>
                  <input id="end-lat" className="input-field" type="number" step="any" value={form.end_lat} onChange={e => setForm({ ...form, end_lat: e.target.value })} placeholder="27.6727" />
                </div>
                <div className="form-group">
                  <label htmlFor="end-lng">Longitude *</label>
                  <input id="end-lng" className="input-field" type="number" step="any" value={form.end_lng} onChange={e => setForm({ ...form, end_lng: e.target.value })} placeholder="85.4319" />
                </div>
              </div>

              {/* Estimates */}
              <p style={{ fontWeight: 600, fontSize: '0.85rem', margin: '12px 0 6px', color: 'var(--text-muted)' }}>Estimates (optional)</p>
              <div className="form-grid">
                <div className="form-group">
                  <label htmlFor="route-dist">Distance (km)</label>
                  <input id="route-dist" className="input-field" type="number" step="0.1" min="0" value={form.expected_distance_km} onChange={e => setForm({ ...form, expected_distance_km: e.target.value })} placeholder="13.5" />
                </div>
                <div className="form-group">
                  <label htmlFor="route-dur">Duration (minutes)</label>
                  <input id="route-dur" className="input-field" type="number" step="1" min="0" value={form.expected_duration_min} onChange={e => setForm({ ...form, expected_duration_min: e.target.value })} placeholder="45" />
                </div>
              </div>

              {/* Active toggle */}
              <div className="form-group">
                <label>Status</label>
                <label className="availability-control">
                  <input type="checkbox" checked={form.is_active} onChange={e => setForm({ ...form, is_active: e.target.checked })} />
                  <span className="toggle-switch"><span className="toggle-slider" /></span>
                  <span>{form.is_active ? 'Active — visible to drivers' : 'Inactive'}</span>
                </label>
              </div>

              {error && (
                <div className="inline-alert error">
                  <AlertCircle size={15} /> {error}
                </div>
              )}
            </div>
            <div className="modal-footer">
              <button className="button button-secondary" onClick={closeModal}>Cancel</button>
              <button
                id="save-route-btn"
                className="button button-primary"
                onClick={handleSave}
                disabled={saving || !form.name || !form.start_name || !form.end_name}
              >
                {saving
                  ? <><RefreshCw className="spin" size={14} /> Saving…</>
                  : <><Save size={14} /> {editRoute ? 'Save Changes' : 'Create Route'}</>
                }
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

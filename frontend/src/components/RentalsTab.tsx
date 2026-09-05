import { useState, useEffect, useCallback, useRef } from 'react';
import { createPortal } from 'react-dom';
import { api } from '../api/auth';
import type { VehicleLocationUpdate } from '../api/vehicles';
import {
  Plus, Edit2, Trash2, Car, RefreshCw, X, Save, AlertCircle,
  User, Phone, Clock, CheckCircle2, XCircle, PlayCircle, RotateCcw,
  Calendar, DollarSign, FileText, Hash, MapPin, Map,
} from 'lucide-react';
import { toast } from '../components/toast';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

delete (L.Icon.Default.prototype as { _getIconUrl?: unknown })._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

/* --------------------------------------------------------------------------
 * Types
 * -------------------------------------------------------------------------- */
interface Vehicle {
  id: number;
  name: string;
  vehicle_type: string;
  number_plate?: string;
  vehicle_status: string;
  is_available: boolean;
}

interface Rental {
  id: number;
  vehicle: number;
  vehicle_name: string;
  vehicle_photo_url?: string | null;
  vehicle_location?: { lat: number; lng: number } | null;
  customer_name: string;
  customer_phone: string;
  customer_id_number: string;
  rental_type: 'daily' | 'hourly' | 'weekly' | 'monthly';
  rate: string;
  deposit: string;
  start_datetime: string;
  expected_return_datetime: string;
  actual_return_datetime: string | null;
  start_odometer_km: number | null;
  end_odometer_km: number | null;
  total_distance_km: number | null;
  start_location_name: string;
  end_location_name: string;
  status: 'reserved' | 'active' | 'overdue' | 'returned' | 'cancelled';
  is_overdue: boolean;
  notes: string;
  created_at: string;
}

interface RentalForm {
  vehicle: string;
  customer_name: string;
  customer_phone: string;
  customer_id_number: string;
  rental_type: string;
  rate: string;
  deposit: string;
  start_datetime: string;
  expected_return_datetime: string;
  start_location_name: string;
  notes: string;
}

interface ReturnForm {
  end_odometer_km: string;
}

const EMPTY_FORM: RentalForm = {
  vehicle: '',
  customer_name: '',
  customer_phone: '',
  customer_id_number: '',
  rental_type: 'daily',
  rate: '',
  deposit: '0',
  start_datetime: '',
  expected_return_datetime: '',
  start_location_name: '',
  notes: '',
};

const RENTAL_TYPES = [
  { value: 'daily', label: 'Daily' },
  { value: 'hourly', label: 'Hourly' },
  { value: 'weekly', label: 'Weekly' },
  { value: 'monthly', label: 'Monthly' },
];

const STATUS_FILTER_OPTIONS = ['all', 'reserved', 'active', 'overdue', 'returned', 'cancelled'] as const;
type StatusFilter = typeof STATUS_FILTER_OPTIONS[number];

/* --------------------------------------------------------------------------
 * Helpers
 * -------------------------------------------------------------------------- */
function fmtDate(dt: string): string {
  return new Date(dt).toLocaleDateString('en-NP', { day: '2-digit', month: 'short', year: 'numeric' });
}

function fmtDateTime(dt: string): string {
  return new Date(dt).toLocaleString('en-NP', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function getStatusClass(status: string): string {
  switch (status) {
    case 'reserved':  return 'rental-reserved';
    case 'active':    return 'rental-active';
    case 'overdue':   return 'rental-overdue';
    case 'returned':  return 'rental-returned';
    case 'cancelled': return 'rental-cancelled';
    default:          return '';
  }
}

function StatusIcon({ status }: { status: string }) {
  switch (status) {
    case 'reserved':  return <Clock size={13} style={{ color: 'var(--warning)' }} />;
    case 'active':    return <Car size={13} style={{ color: 'var(--success)' }} />;
    case 'overdue':   return <AlertCircle size={13} style={{ color: 'var(--danger)' }} />;
    case 'returned':  return <CheckCircle2 size={13} style={{ color: 'var(--text-muted)' }} />;
    case 'cancelled': return <XCircle size={13} style={{ color: 'var(--danger)', opacity: 0.75 }} />;
    default: return null;
  }
}

// Format a JS Date to datetime-local input string (YYYY-MM-DDTHH:MM)
function toDatetimeLocal(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/* --------------------------------------------------------------------------
 * LiveMarker — moves the marker and pans the map when a new GPS fix arrives
 * -------------------------------------------------------------------------- */
function LiveMarker({ position }: { position: [number, number] }) {
  const markerRef = useRef<L.Marker | null>(null);
  const map = useMap();
  useEffect(() => {
    if (markerRef.current) {
      markerRef.current.setLatLng(position);
    }
    map.panTo(position, { animate: true, duration: 0.8 });
  }, [position, map]);
  return <Marker ref={markerRef} position={position} />;
}

/* --------------------------------------------------------------------------
 * Props
 * -------------------------------------------------------------------------- */
interface RentalsTabProps {
  vehicleLocationUpdates?: Map<number, VehicleLocationUpdate>;
}

/* --------------------------------------------------------------------------
 * Main Component
 * -------------------------------------------------------------------------- */
export default function RentalsTab({ vehicleLocationUpdates }: RentalsTabProps) {
  const [rentals, setRentals] = useState<Rental[]>([]);
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');

  // Modals
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editRental, setEditRental] = useState<Rental | null>(null);
  const [form, setForm] = useState<RentalForm>(EMPTY_FORM);

  // Return dialog
  const [returnRental, setReturnRental] = useState<Rental | null>(null);
  const [returnForm, setReturnForm] = useState<ReturnForm>({ end_odometer_km: '' });

  // Detail expand
  const [expandedId, setExpandedId] = useState<number | null>(null);

  // Tracking modal
  const [trackingRental, setTrackingRental] = useState<Rental | null>(null);

  // Derive the live position: prefer WS update, fallback to REST snapshot
  const livePosition = trackingRental
    ? vehicleLocationUpdates?.get(trackingRental.vehicle)
      ?? (trackingRental.vehicle_location
          ? { vehicle_id: trackingRental.vehicle, lat: trackingRental.vehicle_location.lat, lng: trackingRental.vehicle_location.lng, timestamp: '' }
          : null)
    : null;

  /* ---------------------------------------------------------------------- */
  const fetchAll = useCallback(async () => {
    try {
      setLoading(true);
      const [rentalsResp, vehiclesResp] = await Promise.all([
        api.get('/rentals/'),
        api.get('/vehicles/'),
      ]);
      setRentals(rentalsResp.data);
      setVehicles(vehiclesResp.data);
    } catch {
      toast.error('Failed to load rental data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  /* ---------------------------------------------------------------------- */
  function defaultStartDatetime(): string {
    const now = new Date();
    return toDatetimeLocal(now);
  }
  function defaultEndDatetime(): string {
    const d = new Date();
    d.setDate(d.getDate() + 1);
    return toDatetimeLocal(d);
  }

  function openCreate() {
    setEditRental(null);
    setForm({
      ...EMPTY_FORM,
      start_datetime: defaultStartDatetime(),
      expected_return_datetime: defaultEndDatetime(),
    });
    setError(null);
    setShowCreateModal(true);
  }

  function openEdit(rental: Rental) {
    setEditRental(rental);
    setForm({
      vehicle: String(rental.vehicle),
      customer_name: rental.customer_name,
      customer_phone: rental.customer_phone,
      customer_id_number: rental.customer_id_number,
      rental_type: rental.rental_type,
      rate: rental.rate,
      deposit: rental.deposit,
      start_datetime: toDatetimeLocal(new Date(rental.start_datetime)),
      expected_return_datetime: toDatetimeLocal(new Date(rental.expected_return_datetime)),
      start_location_name: rental.start_location_name,
      notes: rental.notes,
    });
    setError(null);
    setShowCreateModal(true);
  }

  function closeModal() {
    setShowCreateModal(false);
    setEditRental(null);
    setError(null);
  }

  /* ---------------------------------------------------------------------- */
  async function handleSave() {
    if (!form.vehicle) { setError('Please select a vehicle.'); return; }
    if (!form.customer_name.trim()) { setError('Customer name is required.'); return; }
    if (!form.rate) { setError('Rental rate is required.'); return; }
    if (!form.start_datetime) { setError('Start date/time is required.'); return; }
    if (!form.expected_return_datetime) { setError('Expected return date/time is required.'); return; }

    const payload = {
      vehicle: parseInt(form.vehicle),
      customer_name: form.customer_name.trim(),
      customer_phone: form.customer_phone.trim(),
      customer_id_number: form.customer_id_number.trim(),
      rental_type: form.rental_type,
      rate: parseFloat(form.rate),
      deposit: parseFloat(form.deposit || '0'),
      start_datetime: new Date(form.start_datetime).toISOString(),
      expected_return_datetime: new Date(form.expected_return_datetime).toISOString(),
      start_location_name: form.start_location_name.trim(),
      notes: form.notes.trim(),
    };

    try {
      setSaving(true);
      setError(null);
      if (editRental) {
        await api.patch(`/rentals/${editRental.id}/`, payload);
        toast.success('Rental updated');
      } else {
        await api.post('/rentals/', payload);
        toast.success('Rental booking created');
      }
      closeModal();
      await fetchAll();
    } catch (err) {
      const e = err as any;
      const data = e.response?.data;
      if (data && 'error' in data) {
        setError(data.error as string);
      } else if (data) {
        const msg = Object.values(data as Record<string, string | string[]>).flat()[0];
        setError(typeof msg === 'string' ? msg : 'Failed to save rental.');
      } else {
        setError('Failed to save rental.');
      }
    } finally {
      setSaving(false);
    }
  }

  /* ---------------------------------------------------------------------- */
  async function handleStart(rental: Rental) {
    if (!window.confirm(`Activate rental #${rental.id} for ${rental.customer_name}?`)) return;
    try {
      await api.post(`/rentals/${rental.id}/start/`);
      toast.success('Rental activated');
      await fetchAll();
    } catch (err) {
      const e = err as any;
      toast.error(e.response?.data?.error || 'Failed to start rental');
    }
  }

  async function handleReturn(rental: Rental) {
    setReturnRental(rental);
    setReturnForm({ end_odometer_km: '' });
  }

  async function submitReturn() {
    if (!returnRental) return;
    try {
      setSaving(true);
      const payload: Record<string, unknown> = {};
      if (returnForm.end_odometer_km) {
        payload.end_odometer_km = parseFloat(returnForm.end_odometer_km);
      }
      await api.post(`/rentals/${returnRental.id}/return/`, payload);
      toast.success('Rental marked as returned');
      setReturnRental(null);
      await fetchAll();
    } catch (err) {
      const e = err as any;
      toast.error(e.response?.data?.error || 'Failed to process return');
    } finally {
      setSaving(false);
    }
  }

  async function handleCancel(rental: Rental) {
    if (!window.confirm(`Cancel rental #${rental.id}? This cannot be undone.`)) return;
    try {
      await api.post(`/rentals/${rental.id}/cancel/`);
      toast.success('Rental cancelled');
      await fetchAll();
    } catch (err) {
      const e = err as any;
      toast.error(e.response?.data?.error || 'Failed to cancel rental');
    }
  }

  async function handleDelete(rental: Rental) {
    if (!window.confirm(`Delete rental #${rental.id}? This action is permanent.`)) return;
    try {
      await api.delete(`/rentals/${rental.id}/`);
      toast.success('Rental deleted');
      await fetchAll();
    } catch {
      toast.error('Failed to delete rental');
    }
  }

  /* ---------------------------------------------------------------------- */
  const filteredRentals = statusFilter === 'all' ? rentals : rentals.filter(r => r.status === statusFilter);

  const stats = {
    total: rentals.length,
    active: rentals.filter(r => r.status === 'active').length,
    reserved: rentals.filter(r => r.status === 'reserved').length,
    overdue: rentals.filter(r => r.status === 'overdue').length,
  };

  /* ---------------------------------------------------------------------- */
  if (loading) return (
    <div style={{ padding: 60, textAlign: 'center', color: 'var(--text-muted)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
      <RefreshCw className="spin" size={24} />
      <span>Loading rentals…</span>
    </div>
  );

  return (
    <div className="tab-content" style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      {/* ── Header ── */}
      <div className="section-toolbar">
        <div>
          <h2 style={{ margin: 0 }}>Vehicle Rentals</h2>
          <span>{filteredRentals.length} rental{filteredRentals.length !== 1 ? 's' : ''} shown</span>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="button button-secondary" onClick={fetchAll}><RefreshCw size={15} /> Refresh</button>
          <button id="create-rental-btn" className="button button-primary" onClick={openCreate}><Plus size={16} /> New Booking</button>
        </div>
      </div>

      {/* ── Summary cards ── */}
      <div className="metrics-grid" style={{ gridTemplateColumns: 'repeat(4, 1fr)' }}>
        <article className="metric-card">
          <div className="metric-heading"><span>Total Bookings</span><Car size={17} /></div>
          <strong>{stats.total}</strong>
          <p>All time</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Active</span><PlayCircle size={17} /></div>
          <strong style={{ color: 'var(--success)' }}>{stats.active}</strong>
          <p>Currently rented</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Reserved</span><Clock size={17} /></div>
          <strong style={{ color: 'var(--accent)' }}>{stats.reserved}</strong>
          <p>Upcoming</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Overdue</span><AlertCircle size={17} /></div>
          <strong style={{ color: stats.overdue > 0 ? 'var(--danger)' : 'inherit' }}>{stats.overdue}</strong>
          <p>Past due date</p>
        </article>
      </div>

      {/* ── Status filter ── */}
      <div className="segmented-control" aria-label="Filter rental status" style={{ alignSelf: 'flex-start' }}>
        {STATUS_FILTER_OPTIONS.map(f => (
          <button
            key={f}
            className={statusFilter === f ? 'active' : ''}
            onClick={() => setStatusFilter(f)}
            style={{ textTransform: 'capitalize' }}
          >
            {f}
            {f === 'overdue' && stats.overdue > 0 && (
              <span className="nav-badge" style={{ marginLeft: 4 }}>{stats.overdue}</span>
            )}
          </button>
        ))}
      </div>

      {/* ── Rental list ── */}
      {filteredRentals.length === 0 ? (
        <div className="empty-state">
          <div className="empty-icon"><Car size={28} /></div>
          <h3>No Rentals Found</h3>
          <p>
            {statusFilter === 'all'
              ? 'Start managing vehicle reservations, active rentals, and returns.'
              : `No ${statusFilter} rentals at the moment.`}
          </p>
          {statusFilter === 'all' && (
            <button className="button button-primary" onClick={openCreate}><Plus size={15} /> Create First Booking</button>
          )}
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {filteredRentals.map(rental => (
            <div
              key={rental.id}
              className="metric-card"
              style={{
                padding: 0,
                overflow: 'hidden',
                borderLeft: rental.is_overdue ? '3px solid var(--danger)' : rental.status === 'active' ? '3px solid var(--success)' : '3px solid transparent',
              }}
            >
              {/* Main row */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 18px', flexWrap: 'wrap' }}>
                {/* Booking ID + status */}
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, minWidth: 60 }}>
                  <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                    <Hash size={10} style={{ display: 'inline', verticalAlign: 'middle' }} />
                    {rental.id}
                  </span>
                  <span className={`status-badge ${getStatusClass(rental.status)}`} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <StatusIcon status={rental.status} />
                    <span style={{ textTransform: 'capitalize', fontSize: '0.72rem' }}>{rental.status}</span>
                  </span>
                </div>

                {/* Vehicle photo + info */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 140 }}>
                  {rental.vehicle_photo_url ? (
                    <img
                      src={rental.vehicle_photo_url}
                      alt={rental.vehicle_name}
                      style={{
                        width: 44,
                        height: 44,
                        borderRadius: 8,
                        objectFit: 'cover',
                        border: '1.5px solid var(--surface-border)',
                        flexShrink: 0,
                      }}
                    />
                  ) : (
                    <div style={{
                      width: 44,
                      height: 44,
                      borderRadius: 8,
                      background: 'var(--surface-hover)',
                      border: '1.5px solid var(--surface-border)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      flexShrink: 0,
                    }}>
                      <Car size={18} style={{ color: 'var(--text-muted)' }} />
                    </div>
                  )}
                  <div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                      <strong style={{ fontSize: '0.88rem' }}>{rental.vehicle_name}</strong>
                    </div>
                    <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', textTransform: 'capitalize' }}>
                      {rental.rental_type} · NPR {Number(rental.rate).toLocaleString()}/unit
                    </span>
                  </div>
                </div>

                {/* Customer */}
                <div style={{ flex: 1, minWidth: 140 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <User size={12} />
                    <span style={{ fontSize: '0.88rem', fontWeight: 600 }}>{rental.customer_name}</span>
                  </div>
                  {rental.customer_phone && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                      <Phone size={11} style={{ color: 'var(--text-muted)' }} />
                      <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{rental.customer_phone}</span>
                    </div>
                  )}
                </div>

                {/* Period */}
                <div style={{ minWidth: 160 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <Calendar size={11} style={{ color: 'var(--text-muted)' }} />
                    <span style={{ fontSize: '0.78rem' }}>{fmtDate(rental.start_datetime)}</span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 5, flexWrap: 'wrap' }}>
                    <span style={{ fontSize: '0.75rem', color: rental.is_overdue ? 'var(--danger)' : 'var(--text-muted)' }}>
                      → {fmtDate(rental.expected_return_datetime)}
                    </span>
                    {rental.is_overdue && (
                      <span style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 3,
                        padding: '1px 5px',
                        borderRadius: 4,
                        background: 'var(--danger-soft)',
                        border: '1px solid color-mix(in srgb, var(--danger) 22%, var(--surface-border))',
                        color: 'var(--danger)',
                        fontSize: '0.62rem',
                        fontWeight: 700,
                        whiteSpace: 'nowrap',
                      }}>
                        ⚠ Overdue
                      </span>
                    )}
                  </div>
                </div>

                {/* Deposit */}
                {Number(rental.deposit) > 0 && (
                  <div style={{ minWidth: 80 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 3 }}>
                      <DollarSign size={11} style={{ color: 'var(--text-muted)' }} />
                      <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Deposit</span>
                    </div>
                    <span style={{ fontSize: '0.82rem', fontWeight: 600 }}>NPR {Number(rental.deposit).toLocaleString()}</span>
                  </div>
                )}

                {/* Actions */}
                <div className="row-actions" style={{ flexShrink: 0, marginLeft: 'auto' }}>
                  {/* Start — only for reserved */}
                  {rental.status === 'reserved' && (
                    <button className="button button-primary" style={{ fontSize: '0.73rem', padding: '4px 10px', minHeight: 28, display: 'inline-flex', alignItems: 'center', gap: 4 }} onClick={() => handleStart(rental)}>
                      <PlayCircle size={13} /> Start
                    </button>
                  )}
                  {/* Return — active/overdue */}
                  {(rental.status === 'active' || rental.status === 'overdue') && (
                    <button className="button button-secondary" style={{ fontSize: '0.73rem', padding: '4px 10px', minHeight: 28, display: 'inline-flex', alignItems: 'center', gap: 4 }} onClick={() => handleReturn(rental)}>
                      <RotateCcw size={13} /> Return
                    </button>
                  )}
                  {/* Cancel — reserved only */}
                  {rental.status === 'reserved' && (
                    <button className="icon-button" style={{ color: 'var(--warning)' }} title="Cancel booking" onClick={() => handleCancel(rental)}>
                      <XCircle size={16} />
                    </button>
                  )}
                  {/* Track active or overdue rental */}
                  {rental.vehicle_location && (
                    <button
                      className="icon-button"
                      style={{ color: 'var(--accent)' }}
                      title="Track vehicle location"
                      onClick={() => setTrackingRental(rental)}
                    >
                      <MapPin size={15} />
                    </button>
                  )}
                  {/* Expand */}
                  <button className="icon-button" title="View details" onClick={() => setExpandedId(expandedId === rental.id ? null : rental.id)}>
                    <FileText size={15} />
                  </button>
                  {/* Edit — not returned/cancelled */}
                  {!['returned', 'cancelled'].includes(rental.status) && (
                    <button className="icon-button" title="Edit" onClick={() => openEdit(rental)}>
                      <Edit2 size={15} />
                    </button>
                  )}
                  {/* Delete — returned/cancelled */}
                  {['returned', 'cancelled'].includes(rental.status) && (
                    <button className="icon-button" style={{ color: 'var(--danger)' }} title="Delete record" onClick={() => handleDelete(rental)}>
                      <Trash2 size={15} />
                    </button>
                  )}
                </div>
              </div>

              {/* Expanded detail panel */}
              {expandedId === rental.id && (
                <div style={{
                  borderTop: '1px solid var(--border)',
                  background: 'var(--surface)',
                  padding: '14px 18px',
                  display: 'grid',
                  gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
                  gap: '12px 24px',
                  fontSize: '0.82rem',
                }}>
                  <DetailField label="Customer ID" value={rental.customer_id_number || '—'} />
                  <DetailField label="Start Time" value={fmtDateTime(rental.start_datetime)} />
                  <DetailField label="Expected Return" value={fmtDateTime(rental.expected_return_datetime)} />
                  {rental.actual_return_datetime && (
                    <DetailField label="Actual Return" value={fmtDateTime(rental.actual_return_datetime)} />
                  )}
                  {rental.start_location_name && (
                    <DetailField label="Pickup Location" value={rental.start_location_name} />
                  )}
                  {rental.start_odometer_km != null && (
                    <DetailField label="Start Odometer" value={`${rental.start_odometer_km.toLocaleString()} km`} />
                  )}
                  {rental.end_odometer_km != null && (
                    <DetailField label="End Odometer" value={`${rental.end_odometer_km.toLocaleString()} km`} />
                  )}
                  {rental.total_distance_km != null && (
                    <DetailField label="Distance Covered" value={`${rental.total_distance_km.toFixed(1)} km`} />
                  )}
                  {rental.notes && (
                    <div style={{ gridColumn: '1 / -1' }}>
                      <span style={{ color: 'var(--text-muted)', display: 'block', marginBottom: 2 }}>Notes</span>
                      <span>{rental.notes}</span>
                    </div>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* ── Create / Edit Modal ── */}
      {showCreateModal && createPortal(
        <div className="modal-overlay" role="presentation" onMouseDown={e => { if (e.target === e.currentTarget) closeModal(); }}>
          <div className="modal-content" role="dialog" aria-modal="true" aria-labelledby="rental-modal-title" style={{ maxWidth: 620 }}>
            <div className="modal-header">
              <div>
                <span>Rental Management</span>
                <h2 id="rental-modal-title">{editRental ? `Edit Rental #${editRental.id}` : 'New Rental Booking'}</h2>
              </div>
              <button className="icon-button" onClick={closeModal} aria-label="Close"><X size={17} /></button>
            </div>
            <div className="modal-body">
              {/* Vehicle select */}
              <div className="form-group">
                <label htmlFor="rental-vehicle">Vehicle *</label>
                <select
                  id="rental-vehicle"
                  className="input-field"
                  value={form.vehicle}
                  onChange={e => setForm({ ...form, vehicle: e.target.value })}
                  disabled={!!editRental}
                >
                  <option value="">— Select a vehicle —</option>
                  {vehicles.map(v => (
                    <option key={v.id} value={v.id}>
                      {v.name}
                      {v.number_plate ? ` (${v.number_plate})` : ''}
                      {!v.is_available ? ' — Unavailable' : ''}
                    </option>
                  ))}
                </select>
                {!editRental && (
                  <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: 3, display: 'block' }}>
                    Note: creating a booking will reserve the selected vehicle.
                  </span>
                )}
              </div>

              {/* Customer info */}
              <p style={{ fontWeight: 600, fontSize: '0.85rem', margin: '12px 0 6px', color: 'var(--text-muted)' }}>Customer Information</p>
              <div className="form-grid">
                <div className="form-group">
                  <label htmlFor="cust-name">Full Name *</label>
                  <input id="cust-name" className="input-field" value={form.customer_name} onChange={e => setForm({ ...form, customer_name: e.target.value })} placeholder="Ram Prasad Sharma" autoFocus={!editRental} />
                </div>
                <div className="form-group">
                  <label htmlFor="cust-phone">Phone</label>
                  <input id="cust-phone" className="input-field" value={form.customer_phone} onChange={e => setForm({ ...form, customer_phone: e.target.value })} placeholder="98XXXXXXXX" />
                </div>
              </div>
              <div className="form-group">
                <label htmlFor="cust-id">Government ID / Citizenship Number</label>
                <input id="cust-id" className="input-field" value={form.customer_id_number} onChange={e => setForm({ ...form, customer_id_number: e.target.value })} placeholder="12-34-5678901" />
              </div>

              {/* Rental terms */}
              <p style={{ fontWeight: 600, fontSize: '0.85rem', margin: '12px 0 6px', color: 'var(--text-muted)' }}>Rental Terms</p>
              <div className="form-grid">
                <div className="form-group">
                  <label htmlFor="rental-type">Rental Type</label>
                  <select id="rental-type" className="input-field" value={form.rental_type} onChange={e => setForm({ ...form, rental_type: e.target.value })}>
                    {RENTAL_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
                  </select>
                </div>
                <div className="form-group">
                  <label htmlFor="rental-rate">Rate (NPR) *</label>
                  <input id="rental-rate" className="input-field" type="number" min="0" step="1" value={form.rate} onChange={e => setForm({ ...form, rate: e.target.value })} placeholder="2500" />
                </div>
                <div className="form-group">
                  <label htmlFor="rental-deposit">Security Deposit (NPR)</label>
                  <input id="rental-deposit" className="input-field" type="number" min="0" step="1" value={form.deposit} onChange={e => setForm({ ...form, deposit: e.target.value })} placeholder="5000" />
                </div>
              </div>

              {/* Dates */}
              <p style={{ fontWeight: 600, fontSize: '0.85rem', margin: '12px 0 6px', color: 'var(--text-muted)' }}>Rental Period</p>
              <div className="form-grid">
                <div className="form-group">
                  <label htmlFor="rental-start">Start Date & Time *</label>
                  <input id="rental-start" className="input-field" type="datetime-local" value={form.start_datetime} onChange={e => setForm({ ...form, start_datetime: e.target.value })} />
                </div>
                <div className="form-group">
                  <label htmlFor="rental-end">Expected Return *</label>
                  <input id="rental-end" className="input-field" type="datetime-local" value={form.expected_return_datetime} onChange={e => setForm({ ...form, expected_return_datetime: e.target.value })} />
                </div>
              </div>

              <div className="form-group">
                <label htmlFor="rental-pickup">Pickup Location</label>
                <input id="rental-pickup" className="input-field" value={form.start_location_name} onChange={e => setForm({ ...form, start_location_name: e.target.value })} placeholder="e.g. Thamel, Kathmandu" />
              </div>

              <div className="form-group">
                <label htmlFor="rental-notes">Notes</label>
                <textarea id="rental-notes" className="input-field" rows={2} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} placeholder="Any additional instructions or conditions…" style={{ resize: 'vertical' }} />
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
                id="save-rental-btn"
                className="button button-primary"
                onClick={handleSave}
                disabled={saving || !form.vehicle || !form.customer_name || !form.rate}
              >
                {saving
                  ? <><RefreshCw className="spin" size={14} /> Saving…</>
                  : <><Save size={14} /> {editRental ? 'Save Changes' : 'Create Booking'}</>
                }
              </button>
            </div>
          </div>
        </div>,
        document.body
      )}

      {/* ── Return Dialog ── */}
      {returnRental && createPortal(
        <div className="modal-overlay" role="presentation" onMouseDown={e => { if (e.target === e.currentTarget) setReturnRental(null); }}>
          <div className="modal-content modal-compact" role="dialog" aria-modal="true" aria-labelledby="return-modal-title">
            <div className="modal-header">
              <div>
                <span>Rental #{returnRental.id}</span>
                <h2 id="return-modal-title">Process Vehicle Return</h2>
              </div>
              <button className="icon-button" onClick={() => setReturnRental(null)} aria-label="Close"><X size={17} /></button>
            </div>
            <div className="modal-body">
              {/* Vehicle photo in return dialog */}
              {returnRental.vehicle_photo_url && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16, padding: '10px 14px', background: 'var(--surface-hover)', borderRadius: 10, border: '1px solid var(--surface-border)' }}>
                  <img
                    src={returnRental.vehicle_photo_url}
                    alt={returnRental.vehicle_name}
                    style={{ width: 60, height: 60, objectFit: 'cover', borderRadius: 8, border: '1.5px solid var(--surface-border)', flexShrink: 0 }}
                  />
                  <div>
                    <strong style={{ fontSize: '0.9rem' }}>{returnRental.vehicle_name}</strong>
                    <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: 2 }}>Customer: {returnRental.customer_name}</div>
                  </div>
                </div>
              )}
              <p style={{ marginBottom: 16, fontSize: '0.88rem', color: 'var(--text-muted)' }}>
                Mark <strong>{returnRental.vehicle_name}</strong> as returned from <strong>{returnRental.customer_name}</strong>.
                {returnRental.is_overdue && (
                  <span style={{ color: 'var(--danger)', display: 'block', marginTop: 4 }}>
                    ⚠ This rental is overdue.
                  </span>
                )}
              </p>
              <div className="form-group">
                <label htmlFor="end-odometer">End Odometer Reading (km)</label>
                <input
                  id="end-odometer"
                  className="input-field"
                  type="number"
                  min="0"
                  step="any"
                  value={returnForm.end_odometer_km}
                  onChange={e => setReturnForm({ end_odometer_km: e.target.value })}
                  placeholder="e.g. 12500 (optional)"
                  autoFocus
                />
              </div>
            </div>
            <div className="modal-footer">
              <button className="button button-secondary" onClick={() => setReturnRental(null)}>Cancel</button>
              <button className="button button-primary" onClick={submitReturn} disabled={saving}>
                {saving
                  ? <><RefreshCw className="spin" size={14} /> Processing…</>
                  : <><CheckCircle2 size={14} /> Confirm Return</>
                }
              </button>
            </div>
          </div>
        </div>,
        document.body
      )}

      {/* ── Tracking Map Modal ── */}
      {trackingRental && trackingRental.vehicle_location && createPortal(
        <div className="modal-overlay" role="presentation" onMouseDown={e => { if (e.target === e.currentTarget) setTrackingRental(null); }}>
          <div className="modal-content modal-wide" role="dialog" aria-modal="true" aria-labelledby="tracking-modal-title">
            <div className="modal-header">
              <div>
                <span>Tracking Active Rental</span>
                <h2 id="tracking-modal-title">{trackingRental.vehicle_name} ({trackingRental.customer_name})</h2>
              </div>
              <button className="icon-button" onClick={() => setTrackingRental(null)} aria-label="Close tracking"><X size={17} /></button>
            </div>
            <div className="modal-body" style={{ padding: 0 }}>
              <div style={{ height: '60vh', width: '100%' }}>
                {livePosition && (
                  <MapContainer
                    center={[livePosition.lat, livePosition.lng]}
                    zoom={15}
                    maxBounds={L.latLngBounds([26.347, 80.058], [30.447, 88.201])}
                    maxBoundsViscosity={1}
                    style={{ width: '100%', height: '100%' }}
                  >
                    <TileLayer url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}" attribution='&copy; Esri' />
                    <LiveMarker position={[livePosition.lat, livePosition.lng]} />
                    <Marker position={[livePosition.lat, livePosition.lng]}>
                      <Popup>
                        <div className="map-popup">
                          <strong>{trackingRental.vehicle_name}</strong>
                          <span>Customer: {trackingRental.customer_name}</span>
                          <span>Odometer: {trackingRental.start_odometer_km ? `${trackingRental.start_odometer_km} km` : '—'}</span>
                          <span className="status-badge active" style={{ marginTop: 4, display: 'inline-block' }}>Rented</span>
                        </div>
                      </Popup>
                    </Marker>
                  </MapContainer>
                )}
              </div>
              <p style={{ padding: '10px 16px', fontSize: '.78rem', color: 'var(--text-muted)', margin: 0, display: 'flex', alignItems: 'center', gap: 8 }}>
                <MapPin size={12} />
                <span className="mono">
                  {livePosition ? `${livePosition.lat.toFixed(5)}, ${livePosition.lng.toFixed(5)}` : 'No GPS fix yet'}
                </span>
                {livePosition?.timestamp && (
                  <span style={{ marginLeft: 'auto' }}>Updated {new Date(livePosition.timestamp).toLocaleTimeString()}</span>
                )}
                {vehicleLocationUpdates?.has(trackingRental.vehicle) && (
                  <span style={{ color: 'var(--success)', display: 'flex', alignItems: 'center', gap: 4 }}>
                    <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--success)', display: 'inline-block', animation: 'pulse 1.5s infinite' }} />
                    Live
                  </span>
                )}
              </p>
            </div>
            <div className="modal-footer">
              <button className="button button-secondary" onClick={() => setTrackingRental(null)}>Close</button>
            </div>
          </div>
        </div>,
        document.body
      )}
    </div>
  );
}

/* --------------------------------------------------------------------------
 * Small helper component for the detail expand panel
 * -------------------------------------------------------------------------- */
function DetailField({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <span style={{ color: 'var(--text-muted)', display: 'block', marginBottom: 1, fontSize: '0.75rem' }}>{label}</span>
      <span>{value}</span>
    </div>
  );
}

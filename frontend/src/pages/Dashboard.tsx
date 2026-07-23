import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Activity, AlertCircle, AlertTriangle, CheckCircle2, ChevronRight, CircleDot,
  Gauge, LayoutDashboard, LogOut, MapPin, Navigation, Phone, Plus,
  Radio, RefreshCw, Search, Settings, ShieldCheck, Trash2, Truck,
  UserRound, Users, Wrench, X,
} from 'lucide-react';
import { GeoJSON, MapContainer, Marker, Polyline, Popup, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';
import { api } from '../api/auth';
import MaintenanceTab from '../components/MaintenanceTab';
import IssuesTab from '../components/IssuesTab';
import ThemeToggle from '../components/ThemeToggle';
import NEPAL_GEOJSON from '../data/nepalBorder';

delete (L.Icon.Default.prototype as { _getIconUrl?: unknown })._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

interface Driver {
  id: number;
  name: string;
  phone_number: string;
  license_number: string;
  is_active: boolean;
}

interface Vehicle {
  id: number;
  name: string;
  vehicle_type: string;
  number_plate?: string;
  is_available: boolean;
  admin_blocked: boolean;
  location: { lat: number; lng: number } | null;
  driver?: number | null;
  driver_name?: string | null;
  has_active_dispatch: boolean;
  active_dispatch_status: string | null;
}

interface IssueReport {
  id: number;
  driver: number;
  driver_name: string;
  vehicle_name: string;
  description: string;
  image: string | null;
  status: 'open' | 'acknowledged' | 'resolved';
  created_at: string;
}

interface DispatchResult {
  assigned_vehicle: { id: number; name: string; lat: number; lng: number };
  status: string;
  distance_km: number;
  duration_min?: number | null;
  geometry?: Array<[number, number]> | null;
}

type Tab = 'dashboard' | 'dispatch' | 'drivers' | 'settings' | 'maintenance' | 'issues';
type StatusFilter = 'all' | 'available' | 'unavailable';

const VEHICLE_TYPES = [
  { value: 'ambulance', label: 'Ambulance' },
  { value: 'logistics', label: 'Logistics' },
  { value: 'municipal', label: 'Municipal' },
];
const NEPAL_CENTER: [number, number] = [28.2, 84.0];
const NEPAL_BOUNDS = L.latLngBounds([26.347, 80.058], [30.447, 88.201]);
const MAP_OPTIONS = {
  maxBounds: NEPAL_BOUNDS,
  maxBoundsViscosity: 1,
  minZoom: 7,
} as const;

const NEPAL_BORDER_STYLE: L.PathOptions = {
  color: '#fbbf24',
  weight: 1.5,
  fillColor: '#fef3c7',
  fillOpacity: 0.08,
};

function MapController({ center }: { center: [number, number] | null }) {
  const map = useMap();
  useEffect(() => {
    if (center && NEPAL_BOUNDS.contains(center)) map.setView(center, 14, { animate: true, duration: 0.7 });
  }, [center, map]);
  return null;
}

function MapClickHandler({ onMapClick }: { onMapClick: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(event) {
      if (NEPAL_BOUNDS.contains(event.latlng)) onMapClick(event.latlng.lat, event.latlng.lng);
    },
  });
  return null;
}

function DispatchMapBoundsFitter({ geometry, requestMarker, assignedVehicle }: {
  geometry: Array<[number, number]> | null | undefined;
  requestMarker: { lat: number; lng: number } | null;
  assignedVehicle: { lat: number; lng: number } | null;
}) {
  const map = useMap();
  useEffect(() => {
    const coordinates: Array<[number, number]> = [];
    if (geometry?.length) coordinates.push(...geometry.filter(point => NEPAL_BOUNDS.contains(point)));
    else if (requestMarker && assignedVehicle) {
      coordinates.push([requestMarker.lat, requestMarker.lng], [assignedVehicle.lat, assignedVehicle.lng]);
    }
    if (coordinates.length >= 2) {
      map.fitBounds(L.latLngBounds(coordinates), { padding: [56, 56], animate: true, duration: 0.7, maxZoom: 15 });
    }
  }, [assignedVehicle, geometry, map, requestMarker]);
  return null;
}

const formatType = (value: string) => value.charAt(0).toUpperCase() + value.slice(1);

// Human-readable label for an active dispatch status.
const DISPATCH_STATUS_LABELS: Record<string, string> = {
  assigned: 'Assigned',
  accepted: 'Accepted',
  en_route: 'En Route',
  arrived: 'On Scene',
};

// Derives the status badge for a vehicle, distinguishing:
//  - Available            → driver on duty, not blocked, no active trip
//  - On Trip / En Route.. → currently on an active dispatch
//  - In service           → unavailable for any other reason (off-duty / admin-blocked)
function getVehicleStatusInfo(vehicle: Vehicle): { label: string; className: string } {
  if (vehicle.is_available) return { label: 'Available', className: 'available' };
  if (vehicle.has_active_dispatch) {
    const label = vehicle.active_dispatch_status
      ? (DISPATCH_STATUS_LABELS[vehicle.active_dispatch_status] || 'On Trip')
      : 'On Trip';
    return { label, className: 'on-trip' };
  }
  return { label: 'In service', className: 'unavailable' };
}

export default function Dashboard() {
  const navigate = useNavigate();
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [activeTab, setActiveTab] = useState<Tab>('dashboard');
  const [selectedVehicleId, setSelectedVehicleId] = useState<number | null>(null);
  const [showVehiclePanel, setShowVehiclePanel] = useState(false);
  const [userOrgType, setUserOrgType] = useState<string | null>(null);
  const [initialLoading, setInitialLoading] = useState(true);
  const [dataError, setDataError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [vehicleQuery, setVehicleQuery] = useState('');
  const [driverQuery, setDriverQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');

  const [showAddModal, setShowAddModal] = useState(false);
  const [newVehicle, setNewVehicle] = useState({
    name: '', vehicle_type: 'ambulance', number_plate: '', is_available: true,
    location: null as { lat: number; lng: number } | null,
  });
  const [addLoading, setAddLoading] = useState(false);
  const [vehicleFormError, setVehicleFormError] = useState<string | null>(null);

  const [showAddDriverModal, setShowAddDriverModal] = useState(false);
  const [newDriver, setNewDriver] = useState({ name: '', phone_number: '', license_number: '', username: '', password: '' });
  const [addDriverLoading, setAddDriverLoading] = useState(false);
  const [driverFormError, setDriverFormError] = useState<string | null>(null);

  const [requestMarker, setRequestMarker] = useState<{ lat: number; lng: number } | null>(null);
  const [dispatchType, setDispatchType] = useState('ambulance');
  const [dispatchResult, setDispatchResult] = useState<DispatchResult | null>(null);
  const [dispatchLoading, setDispatchLoading] = useState(false);
  const [dispatchError, setDispatchError] = useState<string | null>(null);
  const [activeDispatch, setActiveDispatch] = useState<DispatchResult | null>(null);
  const [issues, setIssues] = useState<IssueReport[]>([]);

  const fetchVehicles = useCallback(async () => {
    try {
      const response = await api.get('/vehicles/');
      setVehicles(previous => JSON.stringify(previous) === JSON.stringify(response.data) ? previous : response.data);
      setDataError(null);
      setLastUpdated(new Date());
    } catch (error) {
      console.error('Failed to fetch vehicles', error);
      setDataError('Fleet data could not be refreshed. Existing data is still shown.');
    }
  }, []);

  const fetchDrivers = useCallback(async () => {
    try {
      const response = await api.get('/drivers/');
      setDrivers(previous => JSON.stringify(previous) === JSON.stringify(response.data) ? previous : response.data);
    } catch (error) {
      console.error('Failed to fetch drivers', error);
      setDataError('Driver data could not be refreshed. Existing data is still shown.');
    }
  }, []);

  const fetchActiveDispatch = useCallback(async () => {
    try {
      const response = await api.get('/dispatch/active/');
      setActiveDispatch(response.data);
    } catch (error) {
      if ((error as { response?: { status?: number } })?.response?.status === 404) {
        setActiveDispatch(null);
        setDispatchResult(null);
      } else {
        console.error('Failed to fetch active dispatch', error);
      }
    }
  }, []);

  const fetchIssues = useCallback(async () => {
    try {
      const { data } = await api.get<IssueReport[]>('/issues/');
      setIssues(previous => JSON.stringify(previous) === JSON.stringify(data) ? previous : data);
    } catch (error) {
      console.error('Failed to fetch issues', error);
    }
  }, []);

  useEffect(() => {
    let mounted = true;

    const load = async () => {
      try {
        const profile = await api.get('/auth/me/');
        if (!mounted) return;
        const orgType = profile.data.organization_type;
        setUserOrgType(orgType);
        if (orgType) {
          setNewVehicle(previous => ({ ...previous, vehicle_type: orgType }));
          setDispatchType(orgType);
        }
      } catch (error) {
        console.error('Failed to fetch user profile', error);
      }
      await Promise.all([fetchVehicles(), fetchDrivers(), fetchActiveDispatch()]);
      if (mounted) setInitialLoading(false);
    };

    load();
    const interval = window.setInterval(() => {
      fetchVehicles();
      fetchDrivers();
      fetchActiveDispatch();
      fetchIssues();
    }, 5000);
    return () => {
      mounted = false;
      window.clearInterval(interval);
    };
  }, [fetchDrivers, fetchVehicles, fetchActiveDispatch]);

  const handleLogout = () => {
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
    navigate('/login');
  };

  const handleAddDriver = async () => {
    if (!newDriver.name || !newDriver.license_number || !newDriver.username || !newDriver.password) return;
    setAddDriverLoading(true);
    setDriverFormError(null);
    try {
      await api.post('/drivers/', newDriver);
      setShowAddDriverModal(false);
      setNewDriver({ name: '', phone_number: '', license_number: '', username: '', password: '' });
      await fetchDrivers();
    } catch (error: unknown) {
      console.error('Failed to add driver', error);
      const responseError = error as { response?: { data?: Record<string, string[] | string> } };
      const data = responseError.response?.data;
      const firstError = data
        ? Object.values(data).flat()[0]
        : null;
      setDriverFormError(typeof firstError === 'string' ? firstError : 'Driver could not be added. Check the details and try again.');
    } finally { setAddDriverLoading(false); }
  };

  const handleDeleteDriver = async (driverId: number) => {
    if (!window.confirm('Delete this driver? This action cannot be undone.')) return;
    try { await api.delete(`/drivers/${driverId}/`); await fetchDrivers(); }
    catch (error) { console.error('Failed to delete driver', error); setDataError('Driver could not be deleted.'); }
  };

  const handleAssignDriver = async (vehicleId: number, driverId: string) => {
    try {
      await api.post(`/vehicles/${vehicleId}/assign-driver/`, { driver_id: driverId === '' ? null : Number(driverId) });
      await fetchVehicles();
    } catch (error) { console.error('Failed to assign driver', error); setDataError('Driver assignment could not be updated.'); }
  };

  const handleAddVehicle = async () => {
    if (!newVehicle.name || !newVehicle.location) return;
    setAddLoading(true);
    setVehicleFormError(null);
    try {
      await api.post('/vehicles/', {
        name: newVehicle.name,
        vehicle_type: newVehicle.vehicle_type,
        number_plate: newVehicle.number_plate || null,
        is_available: newVehicle.is_available,
        location: newVehicle.location,
      });
      setShowAddModal(false);
      setNewVehicle({ name: '', vehicle_type: userOrgType || 'ambulance', number_plate: '', is_available: true, location: null });
      await fetchVehicles();
    } catch (error) {
      console.error('Failed to add vehicle', error);
      setVehicleFormError('Vehicle could not be added. Check the details and map location.');
    } finally { setAddLoading(false); }
  };

  const handleToggleAvailability = async (vehicle: Vehicle) => {
    try { await api.patch(`/vehicles/${vehicle.id}/`, { admin_blocked: !vehicle.admin_blocked }); await fetchVehicles(); }
    catch (error) { console.error('Failed to toggle availability', error); setDataError('Vehicle status could not be updated.'); }
  };

  const handleDeleteVehicle = async (vehicleId: number) => {
    if (!window.confirm('Delete this vehicle? This action cannot be undone.')) return;
    try { await api.delete(`/vehicles/${vehicleId}/`); await fetchVehicles(); }
    catch (error) { console.error('Failed to delete vehicle', error); setDataError('Vehicle could not be deleted.'); }
  };

  const handleDispatch = async () => {
    if (!requestMarker) return;
    setDispatchLoading(true); setDispatchError(null); setDispatchResult(null);
    try {
      const response = await api.post('/dispatch/', { lat: requestMarker.lat, lng: requestMarker.lng, vehicle_type: dispatchType });
      setDispatchResult(response.data);
      await fetchVehicles();
    } catch (error: unknown) {
      const responseError = error as { response?: { data?: { error?: string } } };
      setDispatchError(responseError.response?.data?.error || 'Dispatch failed. Try another location or vehicle type.');
    } finally { setDispatchLoading(false); }
  };

  const handleAcceptDispatch = async () => {
    if (!dispatchResult) return;
    try {
      const response = await api.post(`/vehicles/${dispatchResult.assigned_vehicle.id}/dispatch/transition/`, { status: 'accepted' });
      setDispatchResult(response.data);
    } catch (error: unknown) {
      const responseError = error as { response?: { data?: { error?: string } } };
      setDispatchError(responseError.response?.data?.error || 'Could not accept the dispatch.');
    }
  };

  const clearDispatch = () => { setRequestMarker(null); setDispatchResult(null); setDispatchError(null); };
  const switchTab = (tab: Tab) => { setActiveTab(tab); if (tab === 'dispatch') clearDispatch(); };

  const totalVehicles = vehicles.length;
  const availableVehicles = vehicles.filter(vehicle => vehicle.is_available).length;
  const unavailableVehicles = totalVehicles - availableVehicles;
  const activeDrivers = drivers.filter(driver => driver.is_active).length;
  const selectedVehicle = vehicles.find(vehicle => vehicle.id === selectedVehicleId);
  const selectedCenter = selectedVehicle?.location ? [selectedVehicle.location.lat, selectedVehicle.location.lng] as [number, number] : null;

  const filteredVehicles = useMemo(() => vehicles.filter(vehicle => {
    const query = vehicleQuery.toLowerCase().trim();
    const matchesQuery = !query || [vehicle.name, vehicle.number_plate, vehicle.driver_name, vehicle.vehicle_type]
      .some(value => value?.toLowerCase().includes(query));
    const matchesStatus = statusFilter === 'all' || (statusFilter === 'available' ? vehicle.is_available : !vehicle.is_available);
    return matchesQuery && matchesStatus;
  }), [statusFilter, vehicleQuery, vehicles]);

  const filteredDrivers = useMemo(() => drivers.filter(driver => {
    const query = driverQuery.toLowerCase().trim();
    return !query || [driver.name, driver.phone_number, driver.license_number].some(value => value.toLowerCase().includes(query));
  }), [driverQuery, drivers]);

  const openIssueDriverIds = useMemo(() => {
    const ids = new Set<number>();
    for (const issue of issues) {
      if (issue.status === 'open') ids.add(issue.driver);
    }
    return ids;
  }, [issues]);

  const createVehicleIcon = useCallback((available: boolean) => L.divIcon({
    className: 'fleet-marker-wrap',
    html: `<span class="fleet-marker ${available ? 'is-available' : 'is-unavailable'}"><span></span></span>`,
    iconSize: [28, 28], iconAnchor: [14, 14],
  }), []);
  const requestIcon = useMemo(() => L.divIcon({
    className: 'fleet-marker-wrap', html: '<span class="request-marker"><span></span></span>', iconSize: [32, 32], iconAnchor: [16, 16],
  }), []);

  const pageMeta: Record<Tab, { title: string; eyebrow: string }> = {
    dashboard: { title: 'Fleet overview', eyebrow: 'Operations' },
    dispatch: { title: 'Dispatch center', eyebrow: 'Live response' },
    drivers: { title: 'Driver management', eyebrow: 'Workforce' },
    maintenance: { title: 'Vehicle maintenance', eyebrow: 'Service' },
    settings: { title: 'Workspace settings', eyebrow: 'Configuration' },
    issues: { title: 'Reported issues', eyebrow: 'Driver feedback' },
  };

  const renderEmpty = (title: string, text: string) => (
    <div className="empty-state"><div className="empty-icon"><Truck size={20} /></div><h3>{title}</h3><p>{text}</p></div>
  );

  return (
    <div className="dashboard-layout">
      <aside className="sidebar" aria-label="Primary navigation">
        <div className="sidebar-header"><div className="brand-mark" style={{ background: 'transparent' }}><img src="/logo.png" alt="Sarathi" style={{ width: '100%', height: '100%', objectFit: 'contain' }} /></div><div><strong>Sarthi</strong><span>Fleet operations</span></div></div>
        <nav className="sidebar-nav">
          <p className="nav-label">Workspace</p>
          <button id="nav-overview" className={`nav-item ${activeTab === 'dashboard' ? 'active' : ''}`} onClick={() => switchTab('dashboard')}><LayoutDashboard size={17} /><span>Overview</span></button>
          <button id="nav-dispatch" className={`nav-item ${activeTab === 'dispatch' ? 'active' : ''}`} onClick={() => switchTab('dispatch')}><Radio size={17} /><span>Dispatch</span><span className="nav-live-dot" /></button>
          <button id="nav-drivers" className={`nav-item ${activeTab === 'drivers' ? 'active' : ''}`} onClick={() => switchTab('drivers')}><Users size={17} /><span>Drivers</span></button>
          <button id="nav-maintenance" className={`nav-item ${activeTab === 'maintenance' ? 'active' : ''}`} onClick={() => switchTab('maintenance')}><Wrench size={17} /><span>Maintenance</span></button>
          <button id="nav-issues" className={`nav-item ${activeTab === 'issues' ? 'active' : ''}`} onClick={() => switchTab('issues')}><AlertTriangle size={17} /><span>Issues</span>{issues.filter(i => i.status === 'open').length > 0 && <span className="nav-badge">{issues.filter(i => i.status === 'open').length}</span>}</button>
          <p className="nav-label nav-label-secondary">System</p>
          <button id="nav-settings" className={`nav-item ${activeTab === 'settings' ? 'active' : ''}`} onClick={() => switchTab('settings')}><Settings size={17} /><span>Settings</span></button>
        </nav>
        <div className="sidebar-status"><span className="status-dot available" /><div><strong>System operational</strong><span>{availableVehicles} units dispatch-ready</span></div></div>
      </aside>

      <main className="main-content">
        <header className="topbar">
          <div className="topbar-title"><span>{pageMeta[activeTab].eyebrow}</span><h1>{pageMeta[activeTab].title}</h1></div>
          <div className="topbar-actions">
            <div className="sync-status"><RefreshCw size={13} />{lastUpdated ? `Updated ${lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : 'Connecting'}</div>
            <ThemeToggle />
            <button id="logout-button" className="icon-button" onClick={handleLogout} title="Log out" aria-label="Log out"><LogOut size={17} /></button>
          </div>
        </header>

        {dataError && <div className="global-alert" role="alert"><AlertCircle size={16} /><span>{dataError}</span><button onClick={() => setDataError(null)} aria-label="Dismiss alert"><X size={15} /></button></div>}

        <div className={`content-area ${activeTab === 'dispatch' ? 'dispatch-content' : ''}`}>
          {activeTab === 'dashboard' && <section className="tab-content" aria-labelledby="overview-heading">
            <div className="page-heading"><div><h2 id="overview-heading">Fleet readiness</h2><p>Live operational status across your Nepal fleet.</p></div><button id="add-vehicle-button" className="button button-primary" onClick={() => { setVehicleFormError(null); setShowAddModal(true); }}><Plus size={16} />Add vehicle</button></div>
            <div className="metrics-grid">
              <article className="metric-card"><div className="metric-heading"><span>Fleet size</span><Truck size={17} /></div><strong>{initialLoading ? '—' : totalVehicles}</strong><p>Total registered vehicles</p></article>
              <article className="metric-card"><div className="metric-heading"><span>Dispatch ready</span><Activity size={17} /></div><strong>{initialLoading ? '—' : availableVehicles}</strong><p><span className="trend-positive"><CircleDot size={12} />Available now</span></p></article>
              <article className="metric-card"><div className="metric-heading"><span>In service</span><Gauge size={17} /></div><strong>{initialLoading ? '—' : unavailableVehicles}</strong><p>Assigned or unavailable</p></article>
              <article className="metric-card"><div className="metric-heading"><span>Drivers</span><Users size={17} /></div><strong>{initialLoading ? '—' : drivers.length}</strong><p>{activeDrivers} marked active</p></article>
            </div>

            <div className="section-toolbar"><div><h2>Vehicles</h2><span>{filteredVehicles.length} of {vehicles.length} units</span></div><div className="toolbar-controls"><div className="search-field"><Search size={15} /><input id="vehicle-search" value={vehicleQuery} onChange={event => setVehicleQuery(event.target.value)} placeholder="Search fleet" aria-label="Search vehicles" /></div><div className="segmented-control" aria-label="Filter vehicle status">{(['all', 'available', 'unavailable'] as StatusFilter[]).map(filter => <button key={filter} className={statusFilter === filter ? 'active' : ''} onClick={() => setStatusFilter(filter)}>{formatType(filter)}</button>)}</div></div></div>

            {initialLoading ? <div className="list-skeleton">{[1, 2, 3].map(item => <div className="skeleton-row" key={item} />)}</div> : filteredVehicles.length === 0 ? renderEmpty(vehicles.length ? 'No matching vehicles' : 'No vehicles registered', vehicles.length ? 'Adjust your search or availability filter.' : 'Add your first vehicle to begin fleet operations.') :
              <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Vehicle</th><th>Type</th><th>Driver</th><th>Status</th><th>Location</th><th><span className="sr-only">Actions</span></th></tr></thead><tbody>{filteredVehicles.map(vehicle => {
                const statusInfo = getVehicleStatusInfo(vehicle);
                return <tr key={vehicle.id} className="clickable-row" onClick={() => { setSelectedVehicleId(vehicle.id); setShowVehiclePanel(true); }}>
                <td><div className="primary-cell"><div className="entity-icon"><Truck size={17} /></div><div><strong>{vehicle.name}</strong>{vehicle.driver && openIssueDriverIds.has(vehicle.driver as number) && <span className="issue-warning-badge" title="Open driver issue"><AlertTriangle size={13} /></span>}<span className="mono">{vehicle.number_plate || 'No registration'}</span></div></div></td>
                <td><span className="type-label">{formatType(vehicle.vehicle_type)}</span></td>
                <td><select className="table-select" value={vehicle.driver || ''} onChange={event => handleAssignDriver(vehicle.id, event.target.value)} aria-label={`Assign driver to ${vehicle.name}`}><option value="">Unassigned</option>{drivers.map(driver => <option key={driver.id} value={driver.id}>{driver.name}</option>)}</select></td>
                <td><span className={`status-badge ${statusInfo.className}`}><span />{statusInfo.label}</span></td>
                <td>{vehicle.location ? <span className="coordinate"><MapPin size={13} />{vehicle.location.lat.toFixed(3)}, {vehicle.location.lng.toFixed(3)}</span> : <span className="muted">Not reported</span>}</td>
                <td><div className="row-actions"><label className="toggle-switch" title={vehicle.admin_blocked ? 'Set available' : 'Block vehicle'}><input type="checkbox" checked={!vehicle.admin_blocked} onChange={() => handleToggleAvailability(vehicle)} /><span className="toggle-slider" /></label><button className="icon-button danger" onClick={() => handleDeleteVehicle(vehicle.id)} title="Delete vehicle" aria-label={`Delete ${vehicle.name}`}><Trash2 size={15} /></button></div></td>
              </tr>;
              })}</tbody></table></div>}
          </section>}

          {activeTab === 'dispatch' && <section className="tab-content dispatch-workspace" aria-labelledby="dispatch-heading">
            <div className="dispatch-rail">
              <div className="dispatch-rail-header"><div><span className="live-label"><span />Live dispatch</span><h2 id="dispatch-heading">New request</h2></div>{requestMarker && <button className="text-button" onClick={clearDispatch}>Clear</button>}</div>
              <div className="dispatch-step"><span className={`step-number ${requestMarker ? 'complete' : ''}`}>{requestMarker ? <CheckCircle2 size={16} /> : '1'}</span><div><strong>Set incident location</strong><p>{requestMarker ? `${requestMarker.lat.toFixed(5)}, ${requestMarker.lng.toFixed(5)}` : 'Select a point inside Nepal on the map.'}</p></div></div>
              <div className="dispatch-step"><span className={`step-number ${requestMarker ? 'active' : ''}`}>2</span><div className="step-content"><strong>Choose response unit</strong><label htmlFor="dispatch-type">Vehicle type</label><select id="dispatch-type" className="input-field" value={dispatchType} onChange={event => setDispatchType(event.target.value)} disabled={!!userOrgType}>{VEHICLE_TYPES.map(type => <option key={type.value} value={type.value}>{type.label}</option>)}</select></div></div>
              <button id="dispatch-nearest-button" className="button button-primary dispatch-button" onClick={handleDispatch} disabled={!requestMarker || dispatchLoading}>{dispatchLoading ? <><RefreshCw className="spin" size={16} />Finding nearest unit</> : <><Navigation size={16} />Dispatch nearest vehicle</>}</button>

              {dispatchResult && <div className="dispatch-result" role="status"><div className="result-title"><CheckCircle2 size={18} /><div><strong>Vehicle dispatched</strong><span>Route confirmed</span></div></div><div className="result-vehicle"><div className="entity-icon success"><Truck size={18} /></div><div><span>Assigned unit</span><strong>{dispatchResult.assigned_vehicle.name}</strong></div><ChevronRight size={16} /></div><div className="result-metrics"><div><span>Distance</span><strong>{dispatchResult.distance_km} km</strong></div><div><span>ETA</span><strong>{dispatchResult.duration_min ? `${Math.round(dispatchResult.duration_min)} min` : 'Route set'}</strong></div></div>{dispatchResult.status === 'assigned' && <button className="button button-primary" style={{ marginTop: 12, width: '100%' }} onClick={handleAcceptDispatch}>Accept dispatch</button>}</div>}
              {dispatchError && <div className="inline-alert error" role="alert"><AlertCircle size={16} /><span>{dispatchError}</span></div>}

              <div className="rail-section"><div className="rail-section-title"><h3>Fleet units</h3><span>{availableVehicles} ready</span></div><div className="unit-list">{vehicles.length === 0 ? <p className="muted">No fleet units available.</p> : vehicles.map(vehicle => {
                const statusInfo = getVehicleStatusInfo(vehicle);
                return <button key={vehicle.id} className={`unit-row ${selectedVehicleId === vehicle.id ? 'selected' : ''}`} onClick={() => setSelectedVehicleId(vehicle.id)} disabled={!vehicle.location}>
                <span className={`unit-status ${statusInfo.className}`} />
                <div><strong>{vehicle.name}</strong><span>{vehicle.driver_name || 'Unassigned'} · {formatType(vehicle.vehicle_type)}</span></div><ChevronRight size={15} /></button>;
              })}</div></div>
            </div>

            <div className="dispatch-map-shell"><div className="map-top-overlay"><span><MapPin size={14} />Nepal operations area</span><span className="map-legend"><i className="available" />Available <i className="unavailable" />In service <i className="request" />Request</span></div>
              <MapContainer center={NEPAL_CENTER} zoom={7} {...MAP_OPTIONS} style={{ width: '100%', height: '100%' }}>
                <TileLayer url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}" attribution='&copy; <a href="https://www.esri.com/en-us/home">Esri</a> &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community' />
                <GeoJSON data={NEPAL_GEOJSON as GeoJSON.GeoJsonObject} style={() => NEPAL_BORDER_STYLE} />
                <MapController center={selectedCenter} />
                <MapClickHandler onMapClick={(lat, lng) => { setRequestMarker({ lat, lng }); setDispatchResult(null); setDispatchError(null); }} />
                <DispatchMapBoundsFitter geometry={dispatchResult?.geometry} requestMarker={requestMarker} assignedVehicle={dispatchResult?.assigned_vehicle || null} />
                {vehicles.map(vehicle => {
                  const statusInfo = getVehicleStatusInfo(vehicle);
                  const popupTextClass = vehicle.is_available ? 'available-text' : (vehicle.has_active_dispatch ? 'on-trip-text' : 'unavailable-text');
                  return vehicle.location && NEPAL_BOUNDS.contains([vehicle.location.lat, vehicle.location.lng]) && <Marker key={vehicle.id} position={[vehicle.location.lat, vehicle.location.lng]} icon={createVehicleIcon(vehicle.is_available)}><Popup><div className="map-popup"><strong>{vehicle.name}</strong><span>{formatType(vehicle.vehicle_type)}</span><span className={popupTextClass}>{statusInfo.label}</span></div></Popup></Marker>;
                })}
                {requestMarker && <Marker position={[requestMarker.lat, requestMarker.lng]} icon={requestIcon}><Popup><div className="map-popup"><strong>Dispatch request</strong><span>{requestMarker.lat.toFixed(5)}, {requestMarker.lng.toFixed(5)}</span></div></Popup></Marker>}
                {activeDispatch?.geometry?.length ? <Polyline positions={activeDispatch.geometry} pathOptions={{ color: '#059669', weight: 5, opacity: 0.9, lineCap: 'round', lineJoin: 'round' }} /> : null}
                {dispatchResult?.geometry?.length ? <Polyline positions={dispatchResult.geometry} pathOptions={{ color: '#2563eb', weight: 5, opacity: 0.9, lineCap: 'round', lineJoin: 'round' }} /> : dispatchResult && requestMarker && <Polyline positions={[[requestMarker.lat, requestMarker.lng], [dispatchResult.assigned_vehicle.lat, dispatchResult.assigned_vehicle.lng]]} pathOptions={{ color: '#2563eb', weight: 4, dashArray: '8 7', opacity: 0.85 }} />}
              </MapContainer>
              <div className="map-hint"><CircleDot size={13} />Click the map to place a request</div>
            </div>
          </section>}

          {activeTab === 'drivers' && <section className="tab-content" aria-labelledby="drivers-heading">
            <div className="page-heading"><div><h2 id="drivers-heading">Driver directory</h2><p>Manage credentials and assignment-ready personnel.</p></div><button id="add-driver-button" className="button button-primary" onClick={() => { setDriverFormError(null); setShowAddDriverModal(true); }}><Plus size={16} />Add driver</button></div>
            <div className="section-toolbar"><div><h2>All drivers</h2><span>{filteredDrivers.length} records</span></div><div className="search-field"><Search size={15} /><input id="driver-search" value={driverQuery} onChange={event => setDriverQuery(event.target.value)} placeholder="Search drivers" aria-label="Search drivers" /></div></div>
            {initialLoading ? <div className="list-skeleton">{[1, 2, 3].map(item => <div className="skeleton-row" key={item} />)}</div> : filteredDrivers.length === 0 ? renderEmpty(drivers.length ? 'No matching drivers' : 'No drivers registered', drivers.length ? 'Try a different name, phone, or license number.' : 'Add a driver to begin assigning fleet units.') : <div className="driver-grid">{filteredDrivers.map(driver => {
              const assignmentCount = vehicles.filter(vehicle => vehicle.driver === driver.id).length;
              return <article className="driver-card" key={driver.id}><div className="driver-card-head"><div className="avatar">{driver.name.split(' ').map(part => part[0]).join('').slice(0, 2).toUpperCase()}</div><span className={`status-badge ${driver.is_active ? 'available' : 'neutral'}`}><span />{driver.is_active ? 'Active' : 'Inactive'}</span><button className="icon-button danger" onClick={() => handleDeleteDriver(driver.id)} title="Delete driver" aria-label={`Delete ${driver.name}`}><Trash2 size={15} /></button></div><h3>{driver.name}</h3><div className="driver-detail"><Phone size={14} /><span>{driver.phone_number || 'No phone number'}</span></div><div className="driver-detail"><ShieldCheck size={14} /><span className="mono">{driver.license_number}</span></div><div className="driver-card-foot"><span>{assignmentCount ? `${assignmentCount} assigned vehicle${assignmentCount > 1 ? 's' : ''}` : 'No vehicle assigned'}</span><UserRound size={15} /></div></article>;
            })}</div>}
          </section>}

          {activeTab === 'maintenance' && <MaintenanceTab />}
          {activeTab === 'issues' && <IssuesTab />}

          {activeTab === 'settings' && <section className="tab-content" aria-labelledby="settings-heading"><div className="page-heading"><div><h2 id="settings-heading">Workspace settings</h2><p>Configuration for your Sarthi operations workspace.</p></div></div><div className="settings-panel"><div className="settings-icon"><Settings size={20} /></div><div><h3>Configuration is not available yet</h3><p>No settings API is currently exposed. This section is intentionally read-only to avoid changing backend behavior.</p></div></div></section>}
        </div>
      </main>

      {showAddModal && <div className="modal-overlay" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setShowAddModal(false); }}><div className="modal-content" role="dialog" aria-modal="true" aria-labelledby="vehicle-modal-title"><div className="modal-header"><div><span>Fleet inventory</span><h2 id="vehicle-modal-title">Add vehicle</h2></div><button className="icon-button" onClick={() => setShowAddModal(false)} aria-label="Close vehicle form"><X size={17} /></button></div><div className="modal-body"><div className="form-grid"><div className="form-group"><label htmlFor="vehicle-name">Vehicle name</label><input id="vehicle-name" className="input-field" value={newVehicle.name} onChange={event => setNewVehicle({ ...newVehicle, name: event.target.value })} placeholder="Ambulance 07" autoFocus /></div><div className="form-group"><label htmlFor="vehicle-plate">Number plate</label><input id="vehicle-plate" className="input-field" value={newVehicle.number_plate} onChange={event => setNewVehicle({ ...newVehicle, number_plate: event.target.value })} placeholder="BA 1 PA 1234" /></div></div><div className="form-grid"><div className="form-group"><label htmlFor="vehicle-type">Vehicle type</label><select id="vehicle-type" className="input-field" value={newVehicle.vehicle_type} onChange={event => setNewVehicle({ ...newVehicle, vehicle_type: event.target.value })} disabled={!!userOrgType}>{VEHICLE_TYPES.map(type => <option key={type.value} value={type.value}>{type.label}</option>)}</select></div><div className="form-group"><label>Initial status</label><label className="availability-control"><input type="checkbox" checked={newVehicle.is_available} onChange={event => setNewVehicle({ ...newVehicle, is_available: event.target.checked })} /><span className="toggle-switch"><span className="toggle-slider" /></span><span>{newVehicle.is_available ? 'Available' : 'Unavailable'}</span></label></div></div><div className="form-group"><div className="label-row"><label>Operating location</label><span>Select a point within Nepal</span></div><div className="mini-map"><MapContainer center={NEPAL_CENTER} zoom={7} {...MAP_OPTIONS} style={{ width: '100%', height: '100%' }}><TileLayer url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}" attribution='&copy; <a href="https://www.esri.com/en-us/home">Esri</a> &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community' /><GeoJSON data={NEPAL_GEOJSON as GeoJSON.GeoJsonObject} style={() => NEPAL_BORDER_STYLE} /><MapClickHandler onMapClick={(lat, lng) => setNewVehicle(previous => ({ ...previous, location: { lat, lng } }))} />{newVehicle.location && <Marker position={[newVehicle.location.lat, newVehicle.location.lng]} />}</MapContainer></div>{newVehicle.location ? <p className="location-confirm"><CheckCircle2 size={14} />Location set: <span className="mono">{newVehicle.location.lat.toFixed(5)}, {newVehicle.location.lng.toFixed(5)}</span></p> : <p className="field-hint"><MapPin size={14} />A location is required before adding the vehicle.</p>}</div>{vehicleFormError && <div className="inline-alert error"><AlertCircle size={16} />{vehicleFormError}</div>}</div><div className="modal-footer"><button className="button button-secondary" onClick={() => setShowAddModal(false)}>Cancel</button><button id="submit-vehicle-button" className="button button-primary" onClick={handleAddVehicle} disabled={!newVehicle.name || !newVehicle.location || addLoading}>{addLoading ? <><RefreshCw className="spin" size={15} />Adding vehicle</> : 'Add vehicle'}</button></div></div></div>}

      {showAddDriverModal && <div className="modal-overlay" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setShowAddDriverModal(false); }}><div className="modal-content modal-compact" role="dialog" aria-modal="true" aria-labelledby="driver-modal-title"><div className="modal-header"><div><span>Driver directory</span><h2 id="driver-modal-title">Add driver</h2></div><button className="icon-button" onClick={() => setShowAddDriverModal(false)} aria-label="Close driver form"><X size={17} /></button></div><div className="modal-body"><div className="form-group"><label htmlFor="driver-name">Full name</label><input id="driver-name" className="input-field" value={newDriver.name} onChange={event => setNewDriver({ ...newDriver, name: event.target.value })} placeholder="Full legal name" autoFocus /></div><div className="form-group"><label htmlFor="driver-phone">Phone number</label><input id="driver-phone" className="input-field" value={newDriver.phone_number} onChange={event => setNewDriver({ ...newDriver, phone_number: event.target.value })} placeholder="98XXXXXXXX" /></div><div className="form-group"><label htmlFor="driver-license">License number</label><input id="driver-license" className="input-field" value={newDriver.license_number} onChange={event => setNewDriver({ ...newDriver, license_number: event.target.value })} placeholder="01-02-003344" /></div><div className="form-group"><label htmlFor="driver-username">Login username</label><input id="driver-username" className="input-field" value={newDriver.username} onChange={event => setNewDriver({ ...newDriver, username: event.target.value })} placeholder="driver01" /></div><div className="form-group"><label htmlFor="driver-password">Login password</label><input id="driver-password" className="input-field" type="password" value={newDriver.password} onChange={event => setNewDriver({ ...newDriver, password: event.target.value })} placeholder="Min 8 characters" /></div>{driverFormError && <div className="inline-alert error"><AlertCircle size={16} />{driverFormError}</div>}</div><div className="modal-footer"><button className="button button-secondary" onClick={() => setShowAddDriverModal(false)}>Cancel</button><button id="submit-driver-button" className="button button-primary" onClick={handleAddDriver} disabled={!newDriver.name || !newDriver.license_number || !newDriver.username || !newDriver.password || addDriverLoading}>{addDriverLoading ? <><RefreshCw className="spin" size={15} />Adding driver</> : 'Add driver'}</button></div></div></div>}
      {showVehiclePanel && (() => {
        const v = vehicles.find(veh => veh.id === selectedVehicleId);
        if (!v) return null;
        const center: [number, number] = v.location
          ? [v.location.lat, v.location.lng]
          : NEPAL_CENTER;
        return (
          <div className="modal-overlay" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setShowVehiclePanel(false); }}>
            <div className="modal-content modal-wide" role="dialog" aria-modal="true" aria-labelledby="vehicle-live-title">
              <div className="modal-header">
                <div><span>Live vehicle</span><h2 id="vehicle-live-title">{v.name}</h2></div>
                <button className="icon-button" onClick={() => setShowVehiclePanel(false)} aria-label="Close live view"><X size={17} /></button>
              </div>
              <div className="modal-body">
                <div className="vehicle-live-meta">
                  <span className="type-label">{formatType(v.vehicle_type)}</span>
                  <span className="mono">{v.number_plate || 'No registration'}</span>
                  <span className={`status-badge ${getVehicleStatusInfo(v).className}`}><span />{getVehicleStatusInfo(v).label}</span>
                  {v.driver_name && <span className="muted">Driver: {v.driver_name}</span>}
                  <span className="muted">{v.location ? `Last: ${v.location.lat.toFixed(4)}, ${v.location.lng.toFixed(4)}` : 'No location reported'}</span>
                </div>
                <div className="vehicle-live-map">
                  <MapContainer center={center} zoom={15} maxBounds={NEPAL_BOUNDS} maxBoundsViscosity={1} style={{ width: '100%', height: '100%' }}>
                    <TileLayer url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}" attribution='&copy; <a href="https://www.esri.com/en-us/home">Esri</a>' />
                    {v.location && <Marker position={[v.location.lat, v.location.lng]} icon={createVehicleIcon(v.is_available)}>
                      <Popup><div className="map-popup"><strong>{v.name}</strong><span>{formatType(v.vehicle_type)}</span></div></Popup>
                    </Marker>}
                    <MapController center={v.location ? [v.location.lat, v.location.lng] : null} />
                  </MapContainer>
                </div>
                <p className="muted vehicle-live-note">Position refreshes automatically with the fleet (every few seconds).</p>
              </div>
            </div>
          </div>
        );
      })()}

    </div>
  );
}

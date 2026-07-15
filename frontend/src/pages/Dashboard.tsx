import { useEffect, useState, useMemo, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutDashboard, Radio, Settings, LogOut, Truck, Activity, Signal, Plus, Trash2, X, MapPin, Navigation, Users } from 'lucide-react';
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap, useMapEvents } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';
import { api } from '../api/auth';
import ThemeToggle from '../components/ThemeToggle';

// Fix leafet default icon issue
delete (L.Icon.Default.prototype as any)._getIconUrl;
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
  location: {
    lat: number;
    lng: number;
  } | null;
  driver?: number | null;
  driver_name?: string | null;
}

interface DispatchResult {
  assigned_vehicle: {
    id: number;
    name: string;
    lat: number;
    lng: number;
  };
  distance_km: number;
}

const VEHICLE_TYPES = [
  { value: 'ambulance', label: 'Ambulance' },
  { value: 'logistics', label: 'Logistics' },
  { value: 'municipal', label: 'Municipal' },
];

const DEFAULT_CENTER = [28.6139, 77.2090] as [number, number];

// Component to handle map panning
const MapController = ({ center }: { center: [number, number] | null }) => {
  const map = useMap();
  useEffect(() => {
    if (center) {
      map.setView(center, 14, { animate: true, duration: 1.5 });
    }
  }, [center, map]);
  return null;
};

// Component to capture clicks on the dispatch map
const DispatchMapClickHandler = ({ onMapClick }: { onMapClick: (lat: number, lng: number) => void }) => {
  useMapEvents({
    click(e) {
      onMapClick(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
};

// Component to capture clicks on the mini-map in the add-vehicle modal
const MiniMapClickHandler = ({ onMapClick }: { onMapClick: (lat: number, lng: number) => void }) => {
  useMapEvents({
    click(e) {
      onMapClick(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
};

const Dashboard = () => {
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [activeTab, setActiveTab] = useState<'dashboard' | 'dispatch' | 'drivers' | 'settings'>('dashboard');
  const [selectedVehicleId, setSelectedVehicleId] = useState<number | null>(null);
  const [userOrgType, setUserOrgType] = useState<string | null>(null);
  const navigate = useNavigate();

  // Add Vehicle Modal state
  const [showAddModal, setShowAddModal] = useState(false);
  const [newVehicle, setNewVehicle] = useState({
    name: '',
    vehicle_type: 'ambulance',
    number_plate: '',
    is_available: true,
    location: null as { lat: number; lng: number } | null,
  });
  const [addLoading, setAddLoading] = useState(false);

  // Add Driver Modal state
  const [showAddDriverModal, setShowAddDriverModal] = useState(false);
  const [newDriver, setNewDriver] = useState({ name: '', phone_number: '', license_number: '' });
  const [addDriverLoading, setAddDriverLoading] = useState(false);

  // Dispatch state
  const [requestMarker, setRequestMarker] = useState<{ lat: number; lng: number } | null>(null);
  const [dispatchType, setDispatchType] = useState('ambulance');
  const [dispatchResult, setDispatchResult] = useState<DispatchResult | null>(null);
  const [dispatchLoading, setDispatchLoading] = useState(false);
  const [dispatchError, setDispatchError] = useState<string | null>(null);

  useEffect(() => {
    fetchUserProfile();
    fetchVehicles();
    fetchDrivers();
    const interval = setInterval(() => { fetchVehicles(); fetchDrivers(); }, 5000);
    return () => clearInterval(interval);
  }, []);

  const fetchUserProfile = async () => {
    try {
      const response = await api.get('/auth/me/');
      const orgType = response.data.organization_type;
      setUserOrgType(orgType);
      if (orgType) {
        setNewVehicle(prev => ({ ...prev, vehicle_type: orgType }));
        setDispatchType(orgType);
      }
    } catch (error) {
      console.error('Failed to fetch user profile', error);
    }
  };

  const fetchVehicles = async () => {
    try {
      const response = await api.get('/vehicles/');
      setVehicles((prev) => {
        const isSame = JSON.stringify(prev) === JSON.stringify(response.data);
        return isSame ? prev : response.data;
      });
    } catch (error) {
      console.error('Failed to fetch vehicles', error);
    }
  };

  const fetchDrivers = async () => {
    try {
      const response = await api.get('/drivers/');
      setDrivers((prev) => {
        const isSame = JSON.stringify(prev) === JSON.stringify(response.data);
        return isSame ? prev : response.data;
      });
    } catch (error) {
      console.error('Failed to fetch drivers', error);
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
    navigate('/login');
  };

  // --- Driver CRUD handlers ---
  const handleAddDriver = async () => {
    if (!newDriver.name || !newDriver.license_number) return;
    setAddDriverLoading(true);
    try {
      await api.post('/drivers/', newDriver);
      setShowAddDriverModal(false);
      setNewDriver({ name: '', phone_number: '', license_number: '' });
      await fetchDrivers();
    } catch (error) {
      console.error('Failed to add driver', error);
    } finally {
      setAddDriverLoading(false);
    }
  };

  const handleDeleteDriver = async (driverId: number) => {
    try {
      await api.delete(`/drivers/${driverId}/`);
      await fetchDrivers();
    } catch (error) {
      console.error('Failed to delete driver', error);
    }
  };

  const handleAssignDriver = async (vehicleId: number, driverId: string) => {
    const dId = driverId === "" ? null : Number(driverId);
    try {
      await api.post(`/vehicles/${vehicleId}/assign-driver/`, { driver_id: dId });
      await fetchVehicles();
    } catch (error) {
      console.error('Failed to assign driver', error);
    }
  };

  // --- Vehicle CRUD handlers ---
  const handleAddVehicle = async () => {
    if (!newVehicle.name || !newVehicle.location) return;
    setAddLoading(true);
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
    } finally {
      setAddLoading(false);
    }
  };

  const handleToggleAvailability = async (vehicle: Vehicle) => {
    try {
      await api.patch(`/vehicles/${vehicle.id}/`, {
        is_available: !vehicle.is_available,
      });
      await fetchVehicles();
    } catch (error) {
      console.error('Failed to toggle availability', error);
    }
  };

  const handleDeleteVehicle = async (vehicleId: number) => {
    try {
      await api.delete(`/vehicles/${vehicleId}/`);
      await fetchVehicles();
    } catch (error) {
      console.error('Failed to delete vehicle', error);
    }
  };

  // --- Dispatch handler ---
  const handleDispatch = async () => {
    if (!requestMarker) return;
    setDispatchLoading(true);
    setDispatchError(null);
    setDispatchResult(null);
    try {
      const response = await api.post('/dispatch/', {
        lat: requestMarker.lat,
        lng: requestMarker.lng,
        vehicle_type: dispatchType,
      });
      setDispatchResult(response.data);
      await fetchVehicles(); // Refresh to show updated is_available
    } catch (error: any) {
      const msg = error.response?.data?.error || 'Dispatch failed';
      setDispatchError(msg);
    } finally {
      setDispatchLoading(false);
    }
  };

  const clearDispatch = () => {
    setRequestMarker(null);
    setDispatchResult(null);
    setDispatchError(null);
  };

  const selectedVehicle = useMemo(() => 
    vehicles.find(v => v.id === selectedVehicleId), 
  [vehicles, selectedVehicleId]);

  const mapCenter = useMemo(() => {
    if (selectedVehicle?.location) {
      return [selectedVehicle.location.lat, selectedVehicle.location.lng] as [number, number];
    }
    return DEFAULT_CENTER;
  }, [selectedVehicle]);

  // --- Icon creators ---
  const createBlinkingIcon = useCallback((available = true) => {
    const color = available ? 'var(--primary)' : 'var(--danger)';
    const rgbaColor = available ? 'rgba(99, 102, 241, 0.7)' : 'rgba(239, 68, 68, 0.7)';
    const rgbaTransparent = available ? 'rgba(99, 102, 241, 0)' : 'rgba(239, 68, 68, 0)';
    const animName = available ? 'pulse-available' : 'pulse-unavailable';
    return L.divIcon({
      className: 'custom-div-icon',
      html: `<div style="width:16px;height:16px;background:${color};border-radius:50%;border:2px solid white;animation:${animName} 2s infinite;"></div>
        <style>
          @keyframes ${animName} {
            0% { transform: scale(0.8); box-shadow: 0 0 0 0 ${rgbaColor}; }
            70% { transform: scale(1); box-shadow: 0 0 0 15px ${rgbaTransparent}; }
            100% { transform: scale(0.8); box-shadow: 0 0 0 0 ${rgbaTransparent}; }
          }
        </style>`,
      iconSize: [16, 16],
      iconAnchor: [8, 8],
    });
  }, []);

  const createStandardIcon = useCallback((available = true) => {
    const color = available ? 'var(--primary)' : 'var(--danger)';
    return L.divIcon({
      className: 'custom-div-icon',
      html: `<div style="width:12px;height:12px;background:${color};border-radius:50%;border:2px solid white;"></div>`,
      iconSize: [12, 12],
      iconAnchor: [6, 6],
    });
  }, []);

  const createRequestIcon = useCallback(() => {
    return L.divIcon({
      className: 'custom-div-icon',
      html: `<div style="width:20px;height:20px;background:#f59e0b;border-radius:50%;border:3px solid white;box-shadow:0 0 12px rgba(245,158,11,0.6);"></div>`,
      iconSize: [20, 20],
      iconAnchor: [10, 10],
    });
  }, []);

  // --- Dashboard map (tracking tab) ---
  const trackingMap = useMemo(() => {
    return (
      <MapContainer 
        center={DEFAULT_CENTER} 
        zoom={5} 
        style={{ width: '100%', height: '100%' }}
      >
        <MapController center={selectedVehicleId ? mapCenter : null} />
        <TileLayer
          url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
        />
        {vehicles.map(v => v.location && (
          <Marker 
            key={v.id} 
            position={[v.location.lat, v.location.lng]}
            icon={selectedVehicleId === v.id ? createBlinkingIcon(v.is_available) : (selectedVehicleId ? createStandardIcon(v.is_available) : createBlinkingIcon(v.is_available))}
          >
            <Popup>
              <strong>{v.name}</strong><br />
              Type: {v.vehicle_type}<br />
              Status: {v.is_available ? '✅ Available' : '❌ Unavailable'}
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    );
  }, [vehicles, selectedVehicleId, mapCenter, createBlinkingIcon, createStandardIcon]);

  // Derived Metrics
  const totalVehicles = vehicles.length;
  const activeVehicles = vehicles.filter(v => v.is_available).length;
  const offlineVehicles = totalVehicles - activeVehicles;

  return (
    <div className="dashboard-layout">
      {/* Sidebar */}
      <div className="sidebar">
        <div className="sidebar-header">
          <h2 style={{ margin: 0, color: 'var(--primary)', display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Truck size={28} />
            Sarathi
          </h2>
        </div>
        <div className="sidebar-nav">
          <div 
            className={`nav-item ${activeTab === 'dashboard' ? 'active' : ''}`}
            onClick={() => setActiveTab('dashboard')}
          >
            <LayoutDashboard size={20} />
            Dashboard
          </div>
          <div 
            className={`nav-item ${activeTab === 'dispatch' ? 'active' : ''}`}
            onClick={() => { setActiveTab('dispatch'); clearDispatch(); }}
          >
            <Radio size={20} />
            Dispatch
          </div>
          <div 
            className={`nav-item ${activeTab === 'drivers' ? 'active' : ''}`}
            onClick={() => setActiveTab('drivers')}
          >
            <Users size={20} />
            Drivers
          </div>
          <div 
            className={`nav-item ${activeTab === 'settings' ? 'active' : ''}`}
            onClick={() => setActiveTab('settings')}
          >
            <Settings size={20} />
            Settings
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="main-content">
        <div className="topbar">
          <div style={{ display: 'flex', gap: '12px' }}>
            <ThemeToggle />
            <button onClick={handleLogout} className="btn-primary" style={{ width: 'auto', display: 'flex', alignItems: 'center', gap: '8px', padding: '8px 16px', background: 'transparent', border: '1px solid var(--surface-border)', color: 'var(--text-main)' }}>
              <LogOut size={16} />
              Logout
            </button>
          </div>
        </div>
        
        <div className="content-area">
          {/* ======================== DASHBOARD TAB ======================== */}
          {activeTab === 'dashboard' && (
            <>
              <h1 style={{ marginTop: 0, marginBottom: '24px' }}>Fleet Overview</h1>
              
              <div className="metrics-row">
                <div className="metric-card glass-panel">
                  <Truck size={24} color="var(--primary)" style={{ marginBottom: '8px' }} />
                  <p className="metric-value">{totalVehicles}</p>
                  <p className="metric-label">Total Vehicles</p>
                </div>
                <div className="metric-card glass-panel">
                  <Activity size={24} color="#10b981" style={{ marginBottom: '8px' }} />
                  <p className="metric-value" style={{ color: '#10b981' }}>{activeVehicles}</p>
                  <p className="metric-label">Active & Available</p>
                </div>
                <div className="metric-card glass-panel">
                  <Signal size={24} color="var(--danger)" style={{ marginBottom: '8px' }} />
                  <p className="metric-value" style={{ color: 'var(--danger)' }}>{offlineVehicles}</p>
                  <p className="metric-label">Unavailable / Offline</p>
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                <h2 style={{ margin: 0 }}>All Vehicles</h2>
                <button
                  className="btn-primary"
                  style={{ width: 'auto', display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 20px', fontSize: '0.9rem' }}
                  onClick={() => setShowAddModal(true)}
                >
                  <Plus size={18} />
                  Add Vehicle
                </button>
              </div>
              <div className="vehicle-list">
                {vehicles.map(vehicle => (
                  <div key={vehicle.id} className="vehicle-card glass-panel" style={{ justifyContent: 'space-between' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '16px', flex: 1, minWidth: 0 }}>
                      <div className="vehicle-icon">
                        <Truck size={24} />
                      </div>
                      <div style={{ minWidth: 0 }}>
                        <h3 style={{ margin: 0, fontSize: '1.1rem' }}>{vehicle.name} {vehicle.number_plate && <span style={{fontSize: '0.8rem', background: 'var(--surface-border)', padding: '2px 6px', borderRadius: '4px', marginLeft: '8px'}}>{vehicle.number_plate}</span>}</h3>
                        <p style={{ margin: '4px 0 0 0', color: 'var(--text-muted)', fontSize: '0.9rem' }}>
                          {vehicle.vehicle_type} • <span style={{ color: vehicle.is_available ? '#10b981' : 'var(--danger)' }}>{vehicle.is_available ? 'Available' : 'Unavailable'}</span>
                        </p>
                      </div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexShrink: 0 }}>
                      {/* Driver Assignment */}
                      <select 
                        className="input-field" 
                        style={{ padding: '6px 12px', width: '150px', fontSize: '0.85rem', minHeight: 'auto' }}
                        value={vehicle.driver || ""}
                        onChange={(e) => handleAssignDriver(vehicle.id, e.target.value)}
                      >
                        <option value="">Unassigned</option>
                        {drivers.map(d => (
                          <option key={d.id} value={d.id}>{d.name}</option>
                        ))}
                      </select>
                      {/* Toggle switch */}
                      <label className="toggle-switch" title={vehicle.is_available ? 'Set Unavailable' : 'Set Available'}>
                        <input
                          type="checkbox"
                          checked={vehicle.is_available}
                          onChange={() => handleToggleAvailability(vehicle)}
                        />
                        <span className="toggle-slider"></span>
                      </label>
                      {/* Delete button */}
                      <button
                        className="icon-btn-danger"
                        title="Delete vehicle"
                        onClick={() => handleDeleteVehicle(vehicle.id)}
                      >
                        <Trash2 size={16} />
                      </button>
                    </div>
                  </div>
                ))}
                {vehicles.length === 0 && (
                  <p style={{ color: 'var(--text-muted)' }}>No vehicles found in the system.</p>
                )}
              </div>
            </>
          )}

          {/* ======================== DISPATCH TAB ======================== */}
          {activeTab === 'dispatch' && (
            <>
              <h1 style={{ marginTop: 0, marginBottom: '24px' }}>Dispatch Center</h1>
              <div className="dispatch-layout">
                {/* Left Panel */}
                <div className="dispatch-panel">
                  {/* Dispatch Controls */}
                  <div className="glass-panel" style={{ padding: '20px', marginBottom: '16px' }}>
                    <h3 style={{ margin: '0 0 16px 0', display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <MapPin size={20} color="var(--primary)" />
                      Dispatch Request
                    </h3>
                    {!requestMarker ? (
                      <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', margin: 0 }}>
                        Click anywhere on the map to set a request location.
                      </p>
                    ) : (
                      <>
                        <div style={{ marginBottom: '12px' }}>
                          <p style={{ margin: '0 0 4px 0', fontSize: '0.85rem', color: 'var(--text-muted)' }}>Request Location</p>
                          <p style={{ margin: 0, fontFamily: 'monospace', fontSize: '0.9rem' }}>
                            {requestMarker.lat.toFixed(5)}, {requestMarker.lng.toFixed(5)}
                          </p>
                        </div>
                        <div className="form-group" style={{ marginBottom: '16px' }}>
                          <label style={{ display: 'block', marginBottom: '6px', fontSize: '0.85rem', color: 'var(--text-muted)' }}>Vehicle Type</label>
                          <select
                            className="input-field"
                            value={dispatchType}
                            onChange={(e) => setDispatchType(e.target.value)}
                            disabled={!!userOrgType}
                            style={userOrgType ? { opacity: 0.7, cursor: 'not-allowed' } : {}}
                          >
                            {VEHICLE_TYPES.map(t => (
                              <option key={t.value} value={t.value}>{t.label}</option>
                            ))}
                          </select>
                        </div>
                        <div style={{ display: 'flex', gap: '8px' }}>
                          <button
                            className="btn-primary"
                            style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}
                            onClick={handleDispatch}
                            disabled={dispatchLoading}
                          >
                            <Navigation size={16} />
                            {dispatchLoading ? 'Dispatching...' : 'Dispatch Nearest Vehicle'}
                          </button>
                          <button
                            className="btn-primary"
                            style={{ width: 'auto', padding: '10px 16px', background: 'transparent', border: '1px solid var(--surface-border)', color: 'var(--text-main)' }}
                            onClick={clearDispatch}
                            title="Clear"
                          >
                            <X size={16} />
                          </button>
                        </div>
                      </>
                    )}
                  </div>

                  {/* Dispatch Result */}
                  {dispatchResult && (
                    <div className="glass-panel dispatch-result" style={{ padding: '20px', marginBottom: '16px' }}>
                      <h3 style={{ margin: '0 0 12px 0', color: '#10b981', display: 'flex', alignItems: 'center', gap: '8px' }}>
                        ✅ Vehicle Dispatched
                      </h3>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                        <div>
                          <p style={{ margin: 0, fontSize: '0.85rem', color: 'var(--text-muted)' }}>Assigned Vehicle</p>
                          <p style={{ margin: 0, fontSize: '1.1rem', fontWeight: 600 }}>{dispatchResult.assigned_vehicle.name}</p>
                        </div>
                        <div>
                          <p style={{ margin: 0, fontSize: '0.85rem', color: 'var(--text-muted)' }}>Distance</p>
                          <p style={{ margin: 0, fontSize: '1.1rem', fontWeight: 600, color: 'var(--primary)' }}>{dispatchResult.distance_km} km</p>
                        </div>
                      </div>
                    </div>
                  )}

                  {/* Dispatch Error */}
                  {dispatchError && (
                    <div className="glass-panel" style={{ padding: '20px', borderColor: 'var(--danger)' }}>
                      <p style={{ margin: 0, color: 'var(--danger)', fontSize: '0.9rem' }}>⚠️ {dispatchError}</p>
                    </div>
                  )}

                  {/* Vehicle List in Dispatch */}
                  <div style={{ marginTop: '8px' }}>
                    <h3 style={{ margin: '0 0 12px 0', color: 'var(--text-muted)', fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '1px' }}>Active Vehicles</h3>
                    <div className="driver-list" style={{ maxHeight: 'calc(100vh - 520px)' }}>
                      {vehicles.map(vehicle => (
                        <div 
                          key={vehicle.id} 
                          className={`vehicle-card glass-panel interactive-card ${selectedVehicleId === vehicle.id ? 'selected' : ''}`}
                          onClick={() => setSelectedVehicleId(vehicle.id)}
                        >
                          <div className="vehicle-icon" style={{ background: vehicle.is_available ? 'rgba(16, 185, 129, 0.1)' : 'rgba(239, 68, 68, 0.1)', color: vehicle.is_available ? '#10b981' : 'var(--danger)' }}>
                            <Truck size={24} />
                          </div>
                          <div>
                            <h3 style={{ margin: 0, fontSize: '1.1rem' }}>{vehicle.name}</h3>
                            <p style={{ margin: '4px 0 0 0', color: 'var(--text-muted)', fontSize: '0.9rem' }}>
                              {vehicle.vehicle_type} • <span style={{ color: vehicle.is_available ? '#10b981' : 'var(--danger)' }}>{vehicle.is_available ? 'Available' : 'Dispatched'}</span>
                            </p>
                          </div>
                        </div>
                      ))}
                      {vehicles.length === 0 && (
                        <p style={{ color: 'var(--text-muted)' }}>No vehicles found.</p>
                      )}
                    </div>
                  </div>
                </div>

                {/* Dispatch Map */}
                <div className="driver-map">
                  <MapContainer 
                    center={DEFAULT_CENTER} 
                    zoom={5} 
                    style={{ width: '100%', height: '100%' }}
                  >
                    <MapController center={selectedVehicleId ? mapCenter : null} />
                    <DispatchMapClickHandler onMapClick={(lat, lng) => {
                      setRequestMarker({ lat, lng });
                      setDispatchResult(null);
                      setDispatchError(null);
                    }} />
                    <TileLayer
                      url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
                      attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
                    />
                    {/* Vehicle markers */}
                    {vehicles.map(v => v.location && (
                      <Marker 
                        key={v.id} 
                        position={[v.location.lat, v.location.lng]}
                        icon={createBlinkingIcon(v.is_available)}
                      >
                        <Popup>
                          <strong>{v.name}</strong><br />
                          Type: {v.vehicle_type}<br />
                          Status: {v.is_available ? '✅ Available' : '🔴 Dispatched'}
                        </Popup>
                      </Marker>
                    ))}
                    {/* Request marker */}
                    {requestMarker && (
                      <Marker
                        position={[requestMarker.lat, requestMarker.lng]}
                        icon={createRequestIcon()}
                      >
                        <Popup>
                          <strong>Dispatch Request</strong><br />
                          {requestMarker.lat.toFixed(5)}, {requestMarker.lng.toFixed(5)}
                        </Popup>
                      </Marker>
                    )}
                    {/* Dispatch line between request and assigned vehicle */}
                    {dispatchResult && requestMarker && (
                      <Polyline
                        positions={[
                          [requestMarker.lat, requestMarker.lng],
                          [dispatchResult.assigned_vehicle.lat, dispatchResult.assigned_vehicle.lng],
                        ]}
                        pathOptions={{
                          color: '#6366f1',
                          weight: 3,
                          dashArray: '10, 6',
                          opacity: 0.8,
                        }}
                      />
                    )}
                  </MapContainer>
                </div>
              </div>
            </>
          )}

          {/* ======================== DRIVERS TAB ======================== */}
          {activeTab === 'drivers' && (
            <>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
                <h1 style={{ margin: 0 }}>Drivers</h1>
                <button
                  className="btn-primary"
                  style={{ width: 'auto', display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 20px', fontSize: '0.9rem' }}
                  onClick={() => setShowAddDriverModal(true)}
                >
                  <Plus size={18} />
                  Add Driver
                </button>
              </div>
              <div className="vehicle-list">
                {drivers.map(driver => (
                  <div key={driver.id} className="vehicle-card glass-panel" style={{ justifyContent: 'space-between' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '16px', flex: 1 }}>
                      <div className="vehicle-icon" style={{ background: 'var(--surface-border)' }}>
                        <Users size={24} color="var(--text-main)" />
                      </div>
                      <div>
                        <h3 style={{ margin: 0, fontSize: '1.1rem' }}>{driver.name}</h3>
                        <p style={{ margin: '4px 0 0 0', color: 'var(--text-muted)', fontSize: '0.9rem' }}>
                          📞 {driver.phone_number} | 🪪 {driver.license_number}
                        </p>
                      </div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexShrink: 0 }}>
                      <button
                        className="icon-btn-danger"
                        title="Delete driver"
                        onClick={() => handleDeleteDriver(driver.id)}
                      >
                        <Trash2 size={16} />
                      </button>
                    </div>
                  </div>
                ))}
                {drivers.length === 0 && (
                  <p style={{ color: 'var(--text-muted)' }}>No drivers found in the system.</p>
                )}
              </div>
            </>
          )}

          {/* ======================== SETTINGS TAB ======================== */}
          {activeTab === 'settings' && (
            <div>
              <h1 style={{ marginTop: 0, marginBottom: '24px' }}>Settings</h1>
              <p style={{ color: 'var(--text-muted)' }}>Configuration options will be available here.</p>
            </div>
          )}
        </div>
      </div>

      {/* ======================== ADD VEHICLE MODAL ======================== */}
      {showAddModal && (
        <div className="modal-overlay" onClick={() => setShowAddModal(false)}>
          <div className="modal-content glass-panel" onClick={(e) => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h2 style={{ margin: 0 }}>Add New Vehicle</h2>
              <button
                className="icon-btn-danger"
                onClick={() => setShowAddModal(false)}
                style={{ background: 'transparent', border: 'none' }}
              >
                <X size={20} />
              </button>
            </div>

            <div className="form-group">
              <label>Vehicle Name</label>
              <input
                className="input-field"
                type="text"
                placeholder="e.g. Ambulance-07"
                value={newVehicle.name}
                onChange={(e) => setNewVehicle({ ...newVehicle, name: e.target.value })}
              />
            </div>

            <div className="form-group">
              <label>Number Plate</label>
              <input
                className="input-field"
                type="text"
                placeholder="e.g. BA-1-PA-1234"
                value={newVehicle.number_plate}
                onChange={(e) => setNewVehicle({ ...newVehicle, number_plate: e.target.value })}
              />
            </div>

            <div className="form-group">
              <label>Vehicle Type</label>
              <select
                className="input-field"
                value={newVehicle.vehicle_type}
                onChange={(e) => setNewVehicle({ ...newVehicle, vehicle_type: e.target.value })}
                disabled={!!userOrgType}
                style={userOrgType ? { opacity: 0.7, cursor: 'not-allowed' } : {}}
              >
                {VEHICLE_TYPES.map(t => (
                  <option key={t.value} value={t.value}>{t.label}</option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label style={{ display: 'flex', alignItems: 'center', gap: '10px', cursor: 'pointer' }}>
                <span>Available</span>
                <label className="toggle-switch" style={{ marginBottom: 0 }}>
                  <input
                    type="checkbox"
                    checked={newVehicle.is_available}
                    onChange={(e) => setNewVehicle({ ...newVehicle, is_available: e.target.checked })}
                  />
                  <span className="toggle-slider"></span>
                </label>
              </label>
            </div>

            <div className="form-group">
              <label>Location <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(click on map)</span></label>
              <div style={{ height: '200px', borderRadius: '12px', overflow: 'hidden', border: '1px solid var(--surface-border)' }}>
                <MapContainer
                  center={DEFAULT_CENTER}
                  zoom={5}
                  style={{ width: '100%', height: '100%' }}
                >
                  <MiniMapClickHandler onMapClick={(lat, lng) => setNewVehicle(prev => ({ ...prev, location: { lat, lng } }))} />
                  <TileLayer
                    url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
                    attribution='&copy; OpenStreetMap &copy; CARTO'
                  />
                  {newVehicle.location && (
                    <Marker position={[newVehicle.location.lat, newVehicle.location.lng]} />
                  )}
                </MapContainer>
              </div>
              {newVehicle.location && (
                <p style={{ margin: '6px 0 0 0', fontSize: '0.85rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>
                  {newVehicle.location.lat.toFixed(5)}, {newVehicle.location.lng.toFixed(5)}
                </p>
              )}
            </div>

            <button
              className="btn-primary"
              onClick={handleAddVehicle}
              disabled={!newVehicle.name || !newVehicle.location || addLoading}
              style={{ marginTop: '8px', opacity: (!newVehicle.name || !newVehicle.location) ? 0.5 : 1 }}
            >
              {addLoading ? 'Adding...' : 'Add Vehicle'}
            </button>
          </div>
        </div>
      )}

      {/* ======================== ADD DRIVER MODAL ======================== */}
      {showAddDriverModal && (
        <div className="modal-overlay" onClick={() => setShowAddDriverModal(false)}>
          <div className="modal-content glass-panel" onClick={(e) => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h2 style={{ margin: 0 }}>Add New Driver</h2>
              <button
                className="icon-btn-danger"
                onClick={() => setShowAddDriverModal(false)}
                style={{ background: 'transparent', border: 'none' }}
              >
                <X size={20} />
              </button>
            </div>

            <div className="form-group">
              <label>Full Name</label>
              <input
                className="input-field"
                type="text"
                placeholder="e.g. John Doe"
                value={newDriver.name}
                onChange={(e) => setNewDriver({ ...newDriver, name: e.target.value })}
              />
            </div>

            <div className="form-group">
              <label>Phone Number</label>
              <input
                className="input-field"
                type="text"
                placeholder="e.g. 9841000000"
                value={newDriver.phone_number}
                onChange={(e) => setNewDriver({ ...newDriver, phone_number: e.target.value })}
              />
            </div>

            <div className="form-group">
              <label>License Number</label>
              <input
                className="input-field"
                type="text"
                placeholder="e.g. 01-02-003344"
                value={newDriver.license_number}
                onChange={(e) => setNewDriver({ ...newDriver, license_number: e.target.value })}
              />
            </div>

            <button
              className="btn-primary"
              onClick={handleAddDriver}
              disabled={!newDriver.name || !newDriver.license_number || addDriverLoading}
              style={{ marginTop: '8px', opacity: (!newDriver.name || !newDriver.license_number) ? 0.5 : 1 }}
            >
              {addDriverLoading ? 'Adding...' : 'Add Driver'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default Dashboard;

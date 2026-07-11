import { useEffect, useState, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutDashboard, Users, Settings, LogOut, Truck, Activity, Signal } from 'lucide-react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
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

interface Vehicle {
  id: number;
  name: string;
  vehicle_type: string;
  is_available: boolean;
  location: {
    lat: number;
    lng: number;
  } | null;
}

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

const Dashboard = () => {
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [activeTab, setActiveTab] = useState<'dashboard' | 'drivers' | 'settings'>('dashboard');
  const [selectedVehicleId, setSelectedVehicleId] = useState<number | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    fetchVehicles();
    const interval = setInterval(fetchVehicles, 5000);
    return () => clearInterval(interval);
  }, []);

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

  const handleLogout = () => {
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
    navigate('/login');
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

  const mapComponent = useMemo(() => {
    const createBlinkingIcon = () => {
      return L.divIcon({
        className: 'custom-div-icon',
        html: '<div class="blinking-tracker"></div>',
        iconSize: [16, 16],
        iconAnchor: [8, 8],
      });
    };
    
    // Create standard dot for unselected
    const createStandardIcon = () => {
      return L.divIcon({
        className: 'custom-div-icon',
        html: '<div style="width:12px;height:12px;background:var(--text-muted);border-radius:50%;border:2px solid white;"></div>',
        iconSize: [12, 12],
        iconAnchor: [6, 6],
      });
    };

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
            icon={selectedVehicleId === v.id ? createBlinkingIcon() : (selectedVehicleId ? createStandardIcon() : createBlinkingIcon())}
          >
            <Popup>
              <strong>{v.name}</strong><br />
              Type: {v.vehicle_type}
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    );
  }, [vehicles, selectedVehicleId, mapCenter]);

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

              <h2 style={{ marginBottom: '16px' }}>All Vehicles</h2>
              <div className="vehicle-list">
                {vehicles.map(vehicle => (
                  <div key={vehicle.id} className="vehicle-card glass-panel">
                    <div className="vehicle-icon">
                      <Truck size={24} />
                    </div>
                    <div>
                      <h3 style={{ margin: 0, fontSize: '1.1rem' }}>{vehicle.name}</h3>
                      <p style={{ margin: '4px 0 0 0', color: 'var(--text-muted)', fontSize: '0.9rem' }}>
                        {vehicle.vehicle_type} • <span style={{ color: vehicle.is_available ? '#10b981' : 'var(--danger)' }}>{vehicle.is_available ? 'Available' : 'Unavailable'}</span>
                      </p>
                    </div>
                  </div>
                ))}
                {vehicles.length === 0 && (
                  <p style={{ color: 'var(--text-muted)' }}>No vehicles found in the system.</p>
                )}
              </div>
            </>
          )}

          {activeTab === 'drivers' && (
            <>
              <h1 style={{ marginTop: 0, marginBottom: '24px' }}>Live Tracking</h1>
              <div className="driver-layout">
                {/* List of Drivers */}
                <div className="driver-list">
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
                          {vehicle.vehicle_type}
                        </p>
                      </div>
                    </div>
                  ))}
                  {vehicles.length === 0 && (
                    <p style={{ color: 'var(--text-muted)' }}>No drivers found.</p>
                  )}
                </div>

                {/* Map View */}
                <div className="driver-map">
                  {mapComponent}
                </div>
              </div>
            </>
          )}

          {activeTab === 'settings' && (
            <div>
              <h1 style={{ marginTop: 0, marginBottom: '24px' }}>Settings</h1>
              <p style={{ color: 'var(--text-muted)' }}>Configuration options will be available here.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default Dashboard;


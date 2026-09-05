import React, { useState, useCallback } from 'react';
import { api } from '../api/auth';
import { toast } from './toast';
import { MapContainer, TileLayer, Marker, Popup, useMap, useMapEvents } from 'react-leaflet';
import { CheckCircle2, Navigation, RefreshCw, AlertCircle, ChevronRight, Truck, Car, Plus, ShieldCheck, MapPin } from 'lucide-react';
import L from 'leaflet';
import { CountUp } from '../hooks/useCountUp';

const NEPAL_BOUNDS = L.latLngBounds([26.347, 80.058], [30.447, 88.201]);

function MapController({ center }: { center: [number, number] | null }) {
  const map = useMap();
  React.useEffect(() => {
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

interface DispatchWorkspaceProps {
  currentUser: any;
  vehicles: any[];
  onDispatchConfirmed: () => void;
  activeDispatch: any | null;
  clearActiveDispatch: () => void;
}

export default function DispatchWorkspace({ currentUser, vehicles, onDispatchConfirmed, activeDispatch, clearActiveDispatch }: DispatchWorkspaceProps) {
  const [requestMode, setRequestMode] = useState<'LOGISTICS' | 'EMERGENCY'>('EMERGENCY');
  const [priority, setPriority] = useState('MEDIUM');
  const [vehicleType, setVehicleType] = useState('government');
  const [capability, setCapability] = useState('');
  
  const [pickupMarker, setPickupMarker] = useState<{ lat: number; lng: number } | null>(null);
  const [destMarker, setDestMarker] = useState<{ lat: number; lng: number } | null>(null);
  const [selectingDest, setSelectingDest] = useState(false);
  
  const [loading, setLoading] = useState(false);
  const [candidates, setCandidates] = useState<any[]>([]);
  const [activeRequest, setActiveRequest] = useState<any | null>(null);

  const requestIcon = L.divIcon({
    className: 'fleet-marker-wrap', html: '<span class="request-marker"><span></span></span>', iconSize: [32, 32], iconAnchor: [16, 16],
  });
  
  const destIcon = L.divIcon({
    className: 'fleet-marker-wrap', html: '<span class="request-marker" style="background:#2563eb"><span></span></span>', iconSize: [32, 32], iconAnchor: [16, 16],
  });

  const handleMapClick = (lat: number, lng: number) => {
    if (selectingDest) {
      setDestMarker({ lat, lng });
      setSelectingDest(false);
    } else {
      setPickupMarker({ lat, lng });
    }
  };

  const handleFindVehicles = async () => {
    if (!pickupMarker) return toast.error("Pickup location required");
    if (requestMode === 'LOGISTICS' && !destMarker) return toast.error("Destination required for logistics");
    
    setLoading(true);
    try {
      // 1. Create Request
      const createRes = await api.post('/dispatch/requests/', {
        request_type: requestMode,
        priority: priority,
        vehicle_type: vehicleType,
        required_capability: capability,
        pickup_lat: pickupMarker.lat,
        pickup_lng: pickupMarker.lng,
        dest_lat: destMarker?.lat,
        dest_lng: destMarker?.lng,
      });
      
      const reqId = createRes.data.id;
      setActiveRequest(createRes.data);
      
      // 2. Find Candidates
      const candRes = await api.post(`/dispatch/requests/${reqId}/find-vehicles/`);
      setCandidates(candRes.data.candidates || []);
      
      if (candRes.data.candidates?.length === 0) {
        toast.error("No eligible vehicles found");
      }
      
    } catch (e: any) {
      toast.error(e.response?.data?.error || 'Failed to find vehicles');
    } finally {
      setLoading(false);
    }
  };

  const handleDispatch = async (vehicleId: number) => {
    if (!activeRequest) return;
    setLoading(true);
    try {
      await api.post(`/dispatch/requests/${activeRequest.id}/dispatch/`, { vehicle_id: vehicleId });
      toast.success("Vehicle dispatched successfully!");
      setCandidates([]);
      setActiveRequest(null);
      setPickupMarker(null);
      setDestMarker(null);
      onDispatchConfirmed();
    } catch (e: any) {
      toast.error(e.response?.data?.error || 'Dispatch failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <section className="tab-content dispatch-workspace" style={{display: 'flex', flexDirection: 'row', gap: 20}}>
      <div className="dispatch-rail" style={{width: 400, flexShrink: 0}}>
        <div className="dispatch-rail-header">
          <div><span className="live-label"><span />Universal Dispatch</span><h2>New Request</h2></div>
          {pickupMarker && <button className="text-button" onClick={() => { setPickupMarker(null); setDestMarker(null); setCandidates([]); }}>Clear</button>}
        </div>
        
        <div className="segmented-control" style={{marginBottom: 20}}>
          <button className={requestMode === 'EMERGENCY' ? 'active' : ''} onClick={() => setRequestMode('EMERGENCY')}>Emergency</button>
          <button className={requestMode === 'LOGISTICS' ? 'active' : ''} onClick={() => setRequestMode('LOGISTICS')}>Logistics</button>
        </div>
        
        <div className="dispatch-step">
          <span className={`step-number ${pickupMarker ? 'complete' : ''}`}>{pickupMarker ? <CheckCircle2 size={16} /> : '1'}</span>
          <div>
            <strong>Set Pickup / Incident Location</strong>
            <p>{pickupMarker ? `${pickupMarker.lat.toFixed(5)}, ${pickupMarker.lng.toFixed(5)}` : 'Click on map'}</p>
            {!pickupMarker && <button className="text-button" onClick={() => setSelectingDest(false)} style={{marginTop: 5}}>Select on Map</button>}
          </div>
        </div>

        {requestMode === 'LOGISTICS' && (
          <div className="dispatch-step">
            <span className={`step-number ${destMarker ? 'complete' : ''}`}>{destMarker ? <CheckCircle2 size={16} /> : '2'}</span>
            <div>
              <strong>Set Destination</strong>
              <p>{destMarker ? `${destMarker.lat.toFixed(5)}, ${destMarker.lng.toFixed(5)}` : 'Click on map'}</p>
              {!destMarker && pickupMarker && <button className="text-button" onClick={() => setSelectingDest(true)} style={{marginTop: 5}}>Select on Map</button>}
            </div>
          </div>
        )}

        <div className="dispatch-step">
          <span className={`step-number ${(requestMode==='LOGISTICS' ? destMarker : pickupMarker) ? 'active' : ''}`}>{requestMode==='LOGISTICS'? '3' : '2'}</span>
          <div className="step-content">
            <strong>Request Details</strong>
            <div style={{display:'flex', gap:10, marginTop:10}}>
              <div style={{flex:1}}>
                <label>Priority</label>
                <select className="input-field" value={priority} onChange={e => setPriority(e.target.value)}>
                  <option value="LOW">Low</option>
                  <option value="MEDIUM">Medium</option>
                  <option value="HIGH">High</option>
                  <option value="CRITICAL">Critical</option>
                </select>
              </div>
              <div style={{flex:1}}>
                <label>Type</label>
                <select className="input-field" value={vehicleType} onChange={e => setVehicleType(e.target.value)}>
                  <option value="government">Government</option>
                  <option value="logistics">Logistics</option>
                  <option value="public_transport">Transit</option>
                  <option value="rental">Rental</option>
                </select>
              </div>
            </div>
            <label style={{marginTop: 10}}>Required Capability (Optional)</label>
            <input className="input-field" placeholder="e.g. Medical, 5 Ton" value={capability} onChange={e => setCapability(e.target.value)} />
          </div>
        </div>

        <button className="button button-primary dispatch-button" onClick={handleFindVehicles} disabled={loading || !pickupMarker || (requestMode==='LOGISTICS' && !destMarker)}>
          {loading ? <><RefreshCw className="spin" size={16} /> Searching engine...</> : <><Navigation size={16} /> Find Candidates</>}
        </button>

        {candidates.length > 0 && (
          <div style={{marginTop: 20}}>
            <h3 style={{fontSize: 14, marginBottom: 10}}>Recommended Vehicles</h3>
            <div style={{display: 'flex', flexDirection: 'column', gap: 10}}>
              {candidates.map((c, i) => (
                <div key={c.vehicle_id} className="glass-panel" style={{padding: 12, borderRadius: 8}}>
                  <div style={{display:'flex', justifyContent:'space-between', alignItems:'center'}}>
                    <strong>#{i+1} {c.vehicle_name}</strong>
                    <span className="mono" style={{color:'var(--success)'}}>Score: {c.score}</span>
                  </div>
                  <p style={{fontSize: 12, color: 'var(--text-muted)', margin: '4px 0'}}>{c.reason}</p>
                  <div style={{display:'flex', gap:10, fontSize:12, marginBottom:10}}>
                    <span>ETA: {c.eta_min}m</span>
                    <span>Dist: {c.distance_km}km</span>
                  </div>
                  <button className="button button-primary" style={{width: '100%', padding: '6px'}} onClick={() => handleDispatch(c.vehicle_id)}>
                    Dispatch {c.vehicle_name}
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      <div style={{flex: 1, borderRadius: 12, overflow: 'hidden', position: 'relative'}}>
        <MapContainer center={[27.7, 85.3]} zoom={13} maxBounds={NEPAL_BOUNDS} style={{ width: '100%', height: '100%' }}>
          <TileLayer url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png" attribution='&copy; OpenStreetMap & CARTO' />
          <MapClickHandler onMapClick={handleMapClick} />
          {pickupMarker && <Marker position={[pickupMarker.lat, pickupMarker.lng]} icon={requestIcon}><Popup>Pickup / Incident</Popup></Marker>}
          {destMarker && <Marker position={[destMarker.lat, destMarker.lng]} icon={destIcon}><Popup>Destination</Popup></Marker>}
          <MapController center={pickupMarker ? [pickupMarker.lat, pickupMarker.lng] : [27.7, 85.3]} />
        </MapContainer>
        {selectingDest && <div style={{position:'absolute', top: 20, left: '50%', transform:'translateX(-50%)', background:'var(--primary)', color:'white', padding:'8px 16px', borderRadius:20, zIndex:1000, boxShadow:'0 4px 12px rgba(0,0,0,0.1)'}}>Click map to set destination</div>}
      </div>
    </section>
  );
}

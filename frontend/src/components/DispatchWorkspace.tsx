import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  Search, MapPin, Navigation, AlertTriangle, CheckCircle2,
  Clock, Shield, Phone, User, Radio, ChevronDown, ChevronUp,
  RefreshCw, X, Compass, Truck, Check, ArrowRight,
  Package, AlertCircle, Wrench, ShieldAlert, ArrowUpRight,
  Boxes, Send, Eye, Map, CornerDownRight, CheckSquare
} from 'lucide-react';
import {
  MapContainer, TileLayer, Marker, Popup, Polyline,
  useMap, useMapEvents, GeoJSON
} from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { api } from '../api/auth';
import { toast } from './toast';
import NEPAL_GEOJSON from '../data/nepalBorder';

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

// Custom Marker Icons
const pickupMarkerIcon = L.divIcon({
  className: 'pickup-target-pin',
  html: `
    <div class="target-pin-wrapper pickup">
      <div class="target-pin-pulse pickup"></div>
      <div class="target-pin-center pickup">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5">
          <circle cx="12" cy="12" r="10"/>
          <path d="M12 8v8M8 12h8"/>
        </svg>
      </div>
    </div>
  `,
  iconSize: [36, 36],
  iconAnchor: [18, 34],
});

const destMarkerIcon = L.divIcon({
  className: 'dest-target-pin',
  html: `
    <div class="target-pin-wrapper dest">
      <div class="target-pin-pulse dest"></div>
      <div class="target-pin-center dest">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5">
          <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/>
          <line x1="4" y1="22" x2="4" y2="15"/>
        </svg>
      </div>
    </div>
  `,
  iconSize: [36, 36],
  iconAnchor: [18, 34],
});

const breakdownMarkerIcon = L.divIcon({
  className: 'breakdown-target-pin',
  html: `
    <div class="target-pin-wrapper breakdown">
      <div class="target-pin-pulse breakdown"></div>
      <div class="target-pin-center breakdown">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5">
          <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/>
          <line x1="12" y1="9" x2="12" y2="13"/>
          <line x1="12" y1="17" x2="12.01" y2="17"/>
        </svg>
      </div>
    </div>
  `,
  iconSize: [38, 38],
  iconAnchor: [19, 36],
});

const vehicleMarkerIcon = (color: string, isBreakdown: boolean) => L.divIcon({
  className: 'fleet-vehicle-marker',
  html: `
    <div class="vehicle-pin-box ${isBreakdown ? 'breakdown-glow' : ''}" style="background: ${color};">
      <div class="vehicle-pin-dot"></div>
    </div>
  `,
  iconSize: [24, 24],
  iconAnchor: [12, 12],
});

export interface Vehicle {
  id: number;
  name: string;
  vehicle_type: string;
  number_plate?: string;
  is_available: boolean;
  admin_blocked: boolean;
  location: { lat: number; lng: number } | null;
  photo_url?: string | null;
  driver?: number | null;
  driver_name?: string | null;
  has_active_dispatch: boolean;
  active_dispatch_status: string | null;
}

interface OperationalLocation {
  id: number;
  name: string;
  category: string;
  address: string;
  lat: number;
  lng: number;
  contact_phone?: string;
}

interface CandidateVehicle {
  vehicle_id: number;
  vehicle_name: string;
  number_plate: string;
  vehicle_type: string;
  photo_url?: string | null;
  driver?: {
    id: number;
    name: string;
    phone_number: string;
    license_number: string;
    is_on_duty: boolean;
  } | null;
  distance_km: number;
  eta_min: number;
  score: number;
  reason: string;
  is_available: boolean;
  vehicle_status: string;
  route_geometry?: Array<[number, number]> | null;
}

interface EmergencyBreakdownRequest {
  id: number;
  user: number;
  emergency_type: string;
  description: string;
  location: { lat: number; lng: number } | null;
  driver_vehicle_name?: string;
  driver_vehicle_id?: number;
  driver_vehicle_plate?: string;
  driver_name?: string;
  driver_phone?: string;
  status: string;
  assigned_vehicle?: number;
  related_dispatch?: number;
  replacement_dispatch?: number;
  related_dispatch_details?: {
    id: number;
    location_name: string;
    address: string;
    pickup_lat: number;
    pickup_lng: number;
    destination_name: string;
    destination_address: string;
    dest_lat: number;
    dest_lng: number;
    cargo_description: string;
    cargo_weight_kg: number;
    status: string;
  } | null;
  created_at: string;
}

interface ActiveDispatch {
  id: number;
  operation_type: 'NORMAL_LOGISTICS' | 'EMERGENCY_REPLACEMENT';
  request_type: 'NORMAL' | 'EMERGENCY';
  priority: string;
  location_name: string;
  address: string;
  request_lat: number;
  request_lng: number;
  dest_lat?: number | null;
  dest_lng?: number | null;
  destination_name?: string | null;
  destination_address?: string | null;
  cargo_description?: string | null;
  cargo_weight_kg?: number | null;
  vehicle_type: string;
  assigned_vehicle: number;
  assigned_vehicle_name: string;
  assigned_vehicle_plate: string;
  assigned_driver_name?: string;
  assigned_driver_phone?: string;
  assigned_vehicle_photo?: string | null;
  failed_vehicle?: number | null;
  failed_vehicle_name?: string | null;
  failed_vehicle_plate?: string | null;
  original_dispatch?: number | null;
  breakdown_reason?: string | null;
  status: string;
  selection_reason?: string;
  distance_km?: number;
  duration_min?: number;
  created_at: string;
  route_geometry?: Array<[number, number]> | null;
}

const EXISTING_VEHICLE_TYPES = [
  { value: 'logistics', label: 'Logistics Fleet' },
  { value: 'company', label: 'Company Vehicle' },
  { value: 'commercial', label: 'Commercial / Cargo' },
  { value: 'rental', label: 'Rental Vehicle' },
  { value: 'public_transport', label: 'Public Transport' },
  { value: 'government', label: 'Government Vehicle' },
  { value: 'personal', label: 'Personal Vehicle' },
];

function MapController({ flyTarget }: { flyTarget: { lat: number; lng: number; zoom?: number } | null }) {
  const map = useMap();
  useEffect(() => {
    if (flyTarget) {
      map.flyTo([flyTarget.lat, flyTarget.lng], flyTarget.zoom || 15, {
        animate: true,
        duration: 1.2,
      });
    }
  }, [flyTarget, map]);
  return null;
}

function MapClickHandler({ onMapClick }: { onMapClick: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(e) {
      if (NEPAL_BOUNDS.contains(e.latlng)) {
        onMapClick(e.latlng.lat, e.latlng.lng);
      }
    },
  });
  return null;
}

interface DispatchWorkspaceProps {
  fleetVehicles: Vehicle[];
  onRefreshVehicles?: () => void;
}

export default function DispatchWorkspace({ fleetVehicles, onRefreshVehicles }: DispatchWorkspaceProps) {
  // Main sub-tabs: 'logistics' (Normal Delivery) | 'recovery' (Emergency Breakdown Recovery) | 'active' (Fleet Operations)
  const [dispatchMode, setDispatchMode] = useState<'logistics' | 'recovery' | 'active'>('logistics');

  // Internal vehicles list to ensure vehicles are always populated even if parent is loading
  const [vehiclesList, setVehiclesList] = useState<Vehicle[]>(fleetVehicles || []);

  useEffect(() => {
    if (fleetVehicles && fleetVehicles.length > 0) {
      setVehiclesList(fleetVehicles);
    }
  }, [fleetVehicles]);

  const fetchVehiclesDirect = useCallback(async () => {
    try {
      const res = await api.get('/vehicles/');
      if (res.data && Array.isArray(res.data)) {
        setVehiclesList(res.data);
      }
    } catch (e) {
      console.error('Failed to load fleet vehicles in dispatch', e);
    }
  }, []);

  useEffect(() => {
    if (!fleetVehicles || fleetVehicles.length === 0) {
      fetchVehiclesDirect();
    }
  }, [fleetVehicles, fetchVehiclesDirect]);

  // Location search active target: 'pickup' | 'destination' | null
  const [activeSearchTarget, setActiveSearchTarget] = useState<'pickup' | 'destination'>('pickup');
  const [searchQuery, setSearchQuery] = useState('');
  const [defaultLocations, setDefaultLocations] = useState<OperationalLocation[]>([]);
  const [searchResults, setSearchResults] = useState<OperationalLocation[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [showSearchResults, setShowSearchResults] = useState(false);
  const searchContainerRef = useRef<HTMLDivElement>(null);

  // Preload operational locations on mount
  useEffect(() => {
    async function loadOperationalLocations() {
      try {
        const res = await api.get('/operational-locations/');
        if (res.data && Array.isArray(res.data)) {
          setDefaultLocations(res.data);
          setSearchResults(res.data);
        }
      } catch (err) {
        console.error('Failed to load operational locations', err);
      }
    }
    loadOperationalLocations();
  }, []);

  // Normal Logistics Delivery Locations
  const [pickupLocation, setPickupLocation] = useState<{
    lat: number;
    lng: number;
    name: string;
    address: string;
  } | null>(null);

  const [destLocation, setDestLocation] = useState<{
    lat: number;
    lng: number;
    name: string;
    address: string;
  } | null>(null);

  // Cargo Information
  const [cargoDescription, setCargoDescription] = useState('');
  const [cargoWeightKg, setCargoWeightKg] = useState('');

  // Existing Vehicle Type Selection (Defaults to 'personal' if fleet contains personal, or first available, or 'logistics')
  const [vehicleType, setVehicleType] = useState('personal');

  // Map Animation Controller
  const [flyTarget, setFlyTarget] = useState<{ lat: number; lng: number; zoom?: number } | null>(null);

  // Normal Logistics Candidate Evaluation
  const [evaluating, setEvaluating] = useState(false);
  const [recommended, setRecommended] = useState<CandidateVehicle | null>(null);
  const [otherCandidates, setOtherCandidates] = useState<CandidateVehicle[]>([]);
  const [selectedCandidate, setSelectedCandidate] = useState<CandidateVehicle | null>(null);
  const [showOtherCandidates, setShowOtherCandidates] = useState(false);
  const [isDispatching, setIsDispatching] = useState(false);

  // Emergency Breakdown Recovery State
  const [breakdownRequests, setBreakdownRequests] = useState<EmergencyBreakdownRequest[]>([]);
  const [selectedBreakdown, setSelectedBreakdown] = useState<EmergencyBreakdownRequest | null>(null);
  const [evaluatingReplacement, setEvaluatingReplacement] = useState(false);
  const [replacementCandidates, setReplacementCandidates] = useState<CandidateVehicle[]>([]);
  const [selectedReplacement, setSelectedReplacement] = useState<CandidateVehicle | null>(null);
  const [isApprovingRecovery, setIsApprovingRecovery] = useState(false);

  // Active Operations List
  const [activeOperations, setActiveOperations] = useState<ActiveDispatch[]>([]);

  // Close search dropdown on click outside
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (searchContainerRef.current && !searchContainerRef.current.contains(e.target as Node)) {
        setShowSearchResults(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Fetch Active Operations & Breakdown Requests independently so one error doesn't block the other
  const refreshOperations = useCallback(async () => {
    try {
      const opsRes = await api.get('/dispatch/active-list/');
      if (opsRes.data && Array.isArray(opsRes.data)) {
        setActiveOperations(opsRes.data);
      }
    } catch (err) {
      console.error('Failed to fetch active dispatches', err);
    }

    try {
      const breakRes = await api.get('/dispatch/breakdown-requests/');
      if (breakRes.data && Array.isArray(breakRes.data)) {
        setBreakdownRequests(breakRes.data);
      }
    } catch (err) {
      console.error('Failed to fetch breakdown requests', err);
    }
  }, []);

  useEffect(() => {
    refreshOperations();
    const timer = setInterval(refreshOperations, 8000);
    return () => clearInterval(timer);
  }, [refreshOperations]);

  // Search Operational Locations from DB or filter preloaded
  useEffect(() => {
    if (!searchQuery.trim()) {
      setSearchResults(defaultLocations);
      return;
    }
    if (searchQuery.length < 2) {
      return;
    }

    const timer = setTimeout(async () => {
      setIsSearching(true);
      try {
        const res = await api.get(`/operational-locations/?q=${encodeURIComponent(searchQuery)}`);
        setSearchResults(res.data);
        setShowSearchResults(true);
      } catch (err) {
        console.error('Failed to search locations', err);
      } finally {
        setIsSearching(false);
      }
    }, 250);

    return () => clearTimeout(timer);
  }, [searchQuery, defaultLocations]);

  // Handle Location Selection from In-Map Search
  const handleSelectLocation = (loc: OperationalLocation) => {
    const newLoc = {
      lat: loc.lat,
      lng: loc.lng,
      name: loc.name,
      address: loc.address,
    };

    if (activeSearchTarget === 'pickup') {
      setPickupLocation(newLoc);
      toast.success(`Pickup set: ${loc.name}`);
    } else {
      setDestLocation(newLoc);
      toast.success(`Destination set: ${loc.name}`);
    }

    setFlyTarget({ lat: loc.lat, lng: loc.lng, zoom: 15 });
    setShowSearchResults(false);
    setSearchQuery('');
  };

  // Map Click Handler for Pickup or Destination
  const handleMapClick = async (lat: number, lng: number) => {
    const formatted = `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
    let title = activeSearchTarget === 'pickup' ? `Pickup Point (${formatted})` : `Destination (${formatted})`;
    let addr = `Map coordinate ${formatted}`;

    try {
      const res = await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1`);
      const data = await res.json();
      if (data && data.display_name) {
        title = data.name || data.address?.road || (activeSearchTarget === 'pickup' ? 'Pickup Location' : 'Destination Depot');
        addr = data.display_name;
      }
    } catch {
      // Fallback to coordinates
    }

    const newLoc = { lat, lng, name: title, address: addr };
    if (activeSearchTarget === 'pickup') {
      setPickupLocation(newLoc);
      toast.success('Pickup coordinates set from map');
    } else {
      setDestLocation(newLoc);
      toast.success('Destination coordinates set from map');
    }
    setFlyTarget({ lat, lng, zoom: 14 });
  };

  // Run Rule-Based Evaluation for Normal Logistics
  const evaluateNormalLogistics = useCallback(async () => {
    if (!pickupLocation) {
      setRecommended(null);
      setOtherCandidates([]);
      setSelectedCandidate(null);
      return;
    }

    setEvaluating(true);
    try {
      const res = await api.post('/dispatch/preview/', {
        lat: pickupLocation.lat,
        lng: pickupLocation.lng,
        vehicle_type: vehicleType,
        operation_type: 'NORMAL_LOGISTICS',
      });

      if (res.data) {
        setRecommended(res.data.recommended || null);
        setOtherCandidates(res.data.candidates || []);
        if (res.data.recommended) {
          setSelectedCandidate(res.data.recommended);
        }
      }
    } catch (err) {
      console.error('Failed to preview eligible vehicles', err);
    } finally {
      setEvaluating(false);
    }
  }, [pickupLocation, vehicleType]);

  useEffect(() => {
    if (dispatchMode === 'logistics' && pickupLocation) {
      evaluateNormalLogistics();
    }
  }, [dispatchMode, pickupLocation, vehicleType, evaluateNormalLogistics]);

  // Confirm Normal Logistics Dispatch
  const handleConfirmLogistics = async () => {
    const candidate = selectedCandidate || recommended;
    if (!candidate || !pickupLocation) {
      toast.error('Please select an eligible vehicle and pickup location.');
      return;
    }

    setIsDispatching(true);
    try {
      const res = await api.post('/dispatch/confirm/', {
        vehicle_id: candidate.vehicle_id,
        pickup_lat: pickupLocation.lat,
        pickup_lng: pickupLocation.lng,
        pickup_name: pickupLocation.name,
        pickup_address: pickupLocation.address,
        dest_lat: destLocation?.lat,
        dest_lng: destLocation?.lng,
        destination_name: destLocation?.name || 'Authorized Depot',
        destination_address: destLocation?.address || 'Nepal Logistics Route',
        cargo_description: cargoDescription,
        cargo_weight_kg: cargoWeightKg,
        distance_km: candidate.distance_km,
        eta_min: candidate.eta_min,
        selection_reason: candidate.reason,
      });

      if (res.data?.success) {
        toast.success(`Logistics delivery dispatched to ${candidate.vehicle_name} (Driver: ${candidate.driver?.name})!`);
        refreshOperations();
        if (onRefreshVehicles) onRefreshVehicles();
        setPickupLocation(null);
        setDestLocation(null);
        setRecommended(null);
        setSelectedCandidate(null);
        setDispatchMode('active');
      }
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error || 'Failed to dispatch logistics operation.';
      toast.error(msg);
    } finally {
      setIsDispatching(false);
    }
  };

  // Evaluate Replacement Truck for Emergency Breakdown
  const evaluateReplacementForBreakdown = async (breakdown: EmergencyBreakdownRequest) => {
    setSelectedBreakdown(breakdown);
    if (!breakdown.location) return;

    setEvaluatingReplacement(true);
    setReplacementCandidates([]);
    setSelectedReplacement(null);
    setFlyTarget({ lat: breakdown.location.lat, lng: breakdown.location.lng, zoom: 15 });

    try {
      // Look for same vehicle type as failed vehicle, or 'logistics' default
      const vType = breakdown.related_dispatch_details?.status ? 'logistics' : 'logistics';
      const res = await api.post('/dispatch/preview/', {
        lat: breakdown.location.lat,
        lng: breakdown.location.lng,
        vehicle_type: vType,
        operation_type: 'EMERGENCY_REPLACEMENT',
        failed_vehicle_id: breakdown.driver_vehicle_id,
      });

      if (res.data) {
        const all = [];
        if (res.data.recommended) all.push(res.data.recommended);
        if (res.data.candidates) all.push(...res.data.candidates);
        setReplacementCandidates(all);
        if (all.length > 0) setSelectedReplacement(all[0]);
      }
    } catch (err) {
      console.error('Failed to evaluate replacement vehicles', err);
    } finally {
      setEvaluatingReplacement(false);
    }
  };

  // Approve Breakdown Recovery Operation
  const handleApproveRecovery = async () => {
    if (!selectedBreakdown || !selectedReplacement) {
      toast.error('Select an eligible replacement truck first.');
      return;
    }

    setIsApprovingRecovery(true);
    try {
      const res = await api.post('/dispatch/approve-recovery/', {
        emergency_id: selectedBreakdown.id,
        replacement_vehicle_id: selectedReplacement.vehicle_id,
        recovery_lat: selectedBreakdown.location?.lat,
        recovery_lng: selectedBreakdown.location?.lng,
        selection_reason: `Fastest replacement response (ETA ${selectedReplacement.eta_min} min, ${selectedReplacement.distance_km} km) to breakdown site.`,
      });

      if (res.data?.success) {
        toast.success(`Replacement truck ${selectedReplacement.vehicle_name} (Driver: ${selectedReplacement.driver?.name}) dispatched for recovery!`);
        refreshOperations();
        if (onRefreshVehicles) onRefreshVehicles();
        setSelectedBreakdown(null);
        setSelectedReplacement(null);
        setDispatchMode('active');
      }
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error || 'Failed to approve recovery.';
      toast.error(msg);
    } finally {
      setIsApprovingRecovery(false);
    }
  };

  // Driver Breakdown Simulation / Trigger
  const handleSimulateBreakdown = async (dispatchId: number) => {
    const reason = window.prompt('Enter vehicle breakdown reason:', 'Mechanical failure reported by driver') || 'Mechanical failure reported by driver';
    try {
      const res = await api.post('/dispatch/driver-breakdown/', {
        dispatch_id: dispatchId,
        breakdown_reason: reason,
      });
      if (res.data?.success) {
        toast.success('Breakdown emergency recorded! Unit flagged for replacement recovery.');
        refreshOperations();
        if (onRefreshVehicles) onRefreshVehicles();
        setDispatchMode('recovery');
      }
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error || 'Failed to record breakdown.';
      toast.error(msg);
    }
  };

  // Advance Operation Status
  const handleAdvanceStatus = async (dispatchId: number, nextStatus: string) => {
    try {
      await api.post(`/dispatch/${dispatchId}/transition/`, { status: nextStatus });
      toast.success(`Operation updated: ${nextStatus.replace(/_/g, ' ')}`);
      refreshOperations();
      if (onRefreshVehicles) onRefreshVehicles();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error || 'Failed to update operation.';
      toast.error(msg);
    }
  };

  return (
    <div className="dispatch-super-workspace">
      {/* Left Control Rail */}
      <aside className="dispatch-command-rail">
        {/* Module Sub-navigation */}
        <div className="dispatch-mode-nav">
          <button
            type="button"
            className={`mode-nav-btn ${dispatchMode === 'logistics' ? 'active' : ''}`}
            onClick={() => setDispatchMode('logistics')}
            title="Create normal cargo logistics dispatch"
          >
            <Package size={15} />
            <span>New Delivery</span>
          </button>
          <button
            type="button"
            className={`mode-nav-btn ${dispatchMode === 'recovery' ? 'active emergency' : ''}`}
            onClick={() => setDispatchMode('recovery')}
            title="Vehicle breakdown recovery"
          >
            <Wrench size={15} />
            <span>Recovery</span>
            {breakdownRequests.filter(b => b.status === 'pending').length > 0 && (
              <span className="emergency-badge-count">
                {breakdownRequests.filter(b => b.status === 'pending').length}
              </span>
            )}
          </button>
          <button
            type="button"
            className={`mode-nav-btn ${dispatchMode === 'active' ? 'active' : ''}`}
            onClick={() => setDispatchMode('active')}
            title="Live fleet operations"
          >
            <Radio size={15} />
            <span>Active ({activeOperations.length})</span>
          </button>
        </div>

        {/* ════════════════════════════════════════════════════════════════════
            MODE 1: NORMAL LOGISTICS DISPATCH
            ════════════════════════════════════════════════════════════════════ */}
        {dispatchMode === 'logistics' && (
          <div className="logistics-flow-stack">
            {/* Step 1: Location Setup */}
            <div className="command-card">
              <div className="card-top-row">
                <div className="step-tag">
                  <MapPin size={15} />
                  <span>1. Delivery Route (Pickup & Destination)</span>
                </div>
              </div>

              {/* Target Switch: Pickup vs Destination */}
              <div className="location-target-switch">
                <button
                  type="button"
                  className={`target-pill ${activeSearchTarget === 'pickup' ? 'active pickup' : ''}`}
                  onClick={() => setActiveSearchTarget('pickup')}
                >
                  <span className="dot pickup" />
                  <span>Pickup Location</span>
                </button>
                <button
                  type="button"
                  className={`target-pill ${activeSearchTarget === 'destination' ? 'active dest' : ''}`}
                  onClick={() => setActiveSearchTarget('destination')}
                >
                  <span className="dot dest" />
                  <span>Destination</span>
                </button>
              </div>

              {/* Pickup Summary */}
              <div className="route-point-box pickup">
                <div className="point-header">
                  <strong>Pickup (Start)</strong>
                  {pickupLocation && (
                    <button className="pill-clear-btn" onClick={() => setPickupLocation(null)}>Clear</button>
                  )}
                </div>
                {pickupLocation ? (
                  <div>
                    <span className="point-title">{pickupLocation.name}</span>
                    <p className="point-addr">{pickupLocation.address}</p>
                    <span className="point-coords">{pickupLocation.lat.toFixed(5)}, {pickupLocation.lng.toFixed(5)}</span>
                  </div>
                ) : (
                  <p className="point-empty">Search or click on map to set start location</p>
                )}
              </div>

              {/* Destination Summary */}
              <div className="route-point-box destination">
                <div className="point-header">
                  <strong>Destination (End)</strong>
                  {destLocation && (
                    <button className="pill-clear-btn" onClick={() => setDestLocation(null)}>Clear</button>
                  )}
                </div>
                {destLocation ? (
                  <div>
                    <span className="point-title">{destLocation.name}</span>
                    <p className="point-addr">{destLocation.address}</p>
                    <span className="point-coords">{destLocation.lat.toFixed(5)}, {destLocation.lng.toFixed(5)}</span>
                  </div>
                ) : (
                  <p className="point-empty">Search or click on map to set delivery destination</p>
                )}
              </div>
            </div>

            {/* Step 2: Cargo & Fleet Type */}
            <div className="command-card">
              <div className="step-tag">
                <Boxes size={15} />
                <span>2. Cargo & Vehicle Specifications</span>
              </div>

              <div className="form-field-group">
                <label>Cargo / Goods Description</label>
                <input
                  type="text"
                  className="styled-input"
                  value={cargoDescription}
                  onChange={(e) => setCargoDescription(e.target.value)}
                  placeholder="e.g. Medical Supplies, FMCG Pallets, Electronics"
                />
              </div>

              <div className="cargo-grid-row">
                <div className="form-field-group">
                  <label>Weight (kg)</label>
                  <input
                    type="number"
                    className="styled-input"
                    value={cargoWeightKg}
                    onChange={(e) => setCargoWeightKg(e.target.value)}
                    placeholder="e.g. 500"
                  />
                </div>
                <div className="form-field-group">
                  <label>Vehicle Type</label>
                  <select
                    className="styled-select"
                    value={vehicleType}
                    onChange={(e) => setVehicleType(e.target.value)}
                  >
                    {EXISTING_VEHICLE_TYPES.map((t) => (
                      <option key={t.value} value={t.value}>{t.label}</option>
                    ))}
                  </select>
                </div>
              </div>
            </div>

            {/* Step 3: Vehicle Recommendation */}
            <div className="command-card">
              <div className="step-tag">
                <CheckCircle2 size={15} />
                <span>3. Recommended Fleet Vehicle (With Assigned Driver)</span>
              </div>

              {evaluating ? (
                <div className="evaluating-state">
                  <RefreshCw size={20} className="spin" />
                  <span>Calculating real road travel time (OSRM) to pickup site...</span>
                </div>
              ) : !pickupLocation ? (
                <p className="placeholder-text">Set a pickup location to rank eligible fleet units.</p>
              ) : recommended ? (
                <div className="recommendation-content">
                  <div className="best-match-pill">
                    <span>★ FASTEST ROAD ETA TO PICKUP</span>
                  </div>

                  <div className="candidate-card primary-candidate selected">
                    <div className="candidate-header">
                      <div className="vehicle-badge-icon">
                        <Truck size={20} />
                      </div>
                      <div className="candidate-info">
                        <h4>{recommended.vehicle_name}</h4>
                        <span className="plate-badge">{recommended.number_plate}</span>
                      </div>
                      <div className="score-badge">
                        <span>Score: {recommended.score}</span>
                      </div>
                    </div>

                    <div className="candidate-metrics-row">
                      <div className="metric-box eta-box">
                        <Clock size={16} />
                        <div>
                          <span className="metric-label">Travel Time to Pickup</span>
                          <strong className="metric-value">{recommended.eta_min} min</strong>
                        </div>
                      </div>
                      <div className="metric-box dist-box">
                        <Compass size={16} />
                        <div>
                          <span className="metric-label">Road Distance</span>
                          <strong className="metric-value">{recommended.distance_km} km</strong>
                        </div>
                      </div>
                    </div>

                    {/* Pre-assigned Driver from Fleet Management */}
                    <div className="driver-info-row">
                      <User size={14} />
                      <span><strong>{recommended.driver?.name || 'Driver Assigned'}</strong> (Fleet Driver)</span>
                      <Phone size={13} className="phone-icon" />
                      <span>{recommended.driver?.phone_number || 'No contact'}</span>
                    </div>

                    <div className="rationale-box">
                      <strong>Selection Rationale:</strong>
                      <p>{recommended.reason}</p>
                    </div>
                  </div>

                  {/* Dispatch Action Button */}
                  <button
                    type="button"
                    className="button button-primary dispatch-now-btn"
                    onClick={handleConfirmLogistics}
                    disabled={isDispatching}
                  >
                    {isDispatching ? (
                      <>
                        <RefreshCw size={16} className="spin" />
                        <span>Dispatching Logistics Delivery...</span>
                      </>
                    ) : (
                      <>
                        <Send size={16} />
                        <span>DISPATCH LOGISTICS DELIVERY</span>
                      </>
                    )}
                  </button>

                  {/* View Other Eligible Vehicles */}
                  {otherCandidates.length > 0 && (
                    <button
                      type="button"
                      className="view-others-toggle-btn"
                      onClick={() => setShowOtherCandidates(!showOtherCandidates)}
                    >
                      <span>{showOtherCandidates ? 'Hide' : 'View'} Alternative Vehicles ({otherCandidates.length})</span>
                      {showOtherCandidates ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                    </button>
                  )}

                  {showOtherCandidates && (
                    <div className="other-candidates-list">
                      {otherCandidates.map((cand) => (
                        <div
                          key={cand.vehicle_id}
                          className={`candidate-card secondary-candidate ${selectedCandidate?.vehicle_id === cand.vehicle_id ? 'selected' : ''}`}
                          onClick={() => setSelectedCandidate(cand)}
                        >
                          <div className="candidate-header">
                            <div>
                              <h5>{cand.vehicle_name}</h5>
                              <span className="plate-badge">{cand.number_plate}</span>
                            </div>
                            <div className="secondary-metrics">
                              <span>{cand.eta_min} min</span>
                              <span className="sep">•</span>
                              <span>{cand.distance_km} km</span>
                            </div>
                          </div>
                          <div className="driver-info-row">
                            <User size={13} />
                            <span>Driver: {cand.driver?.name}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              ) : (
                <div className="diagnostics-panel">
                  <div className="diag-header">
                    <AlertCircle size={18} />
                    <strong>No Available {vehicleType.toUpperCase()} Units</strong>
                  </div>
                  <p className="diag-action">Ensure fleet units are active, have assigned drivers on duty, and are not busy on other trips.</p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* ════════════════════════════════════════════════════════════════════
            MODE 2: EMERGENCY VEHICLE BREAKDOWN RECOVERY
            ════════════════════════════════════════════════════════════════════ */}
        {dispatchMode === 'recovery' && (
          <div className="breakdown-flow-stack">
            <div className="emergency-header-card">
              <div className="emergency-badge-title">
                <Wrench size={18} />
                <span>Vehicle Breakdown Recovery Center</span>
              </div>
              <p>When an active delivery vehicle fails mid-route, dispatch a replacement truck to receive cargo at the breakdown site and continue to the original destination.</p>
            </div>

            {/* Breakdown Incident Requests Queue */}
            <div className="command-card">
              <div className="step-tag">
                <AlertTriangle size={15} />
                <span>Pending Breakdown Incident Reports ({breakdownRequests.filter(b => b.status === 'pending').length})</span>
              </div>

              {breakdownRequests.length === 0 ? (
                <p className="placeholder-text">No active vehicle breakdowns reported. Fleet operations are running normally.</p>
              ) : (
                <div className="breakdown-requests-list">
                  {breakdownRequests.map((req) => (
                    <div
                      key={req.id}
                      className={`breakdown-item-card ${selectedBreakdown?.id === req.id ? 'active' : ''}`}
                      onClick={() => evaluateReplacementForBreakdown(req)}
                    >
                      <div className="breakdown-item-head">
                        <div>
                          <strong>{req.driver_vehicle_name || 'Fleet Unit'} ({req.driver_vehicle_plate || 'Plate'})</strong>
                          <span className="driver-sub">Driver: {req.driver_name}</span>
                        </div>
                        <span className={`status-pill ${req.status}`}>
                          {req.status.toUpperCase()}
                        </span>
                      </div>

                      <p className="breakdown-desc">{req.description}</p>

                      {req.location && (
                        <div className="breakdown-gps-tag">
                          <MapPin size={13} />
                          <span>GPS: {req.location.lat.toFixed(5)}, {req.location.lng.toFixed(5)}</span>
                        </div>
                      )}

                      <button
                        type="button"
                        className="button button-primary select-breakdown-btn"
                        onClick={(e) => {
                          e.stopPropagation();
                          evaluateReplacementForBreakdown(req);
                        }}
                      >
                        <Eye size={14} />
                        <span>Inspect & Find Replacement</span>
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Replacement Truck Finder & Recovery Action */}
            {selectedBreakdown && (
              <div className="command-card replacement-card">
                <div className="step-tag">
                  <Truck size={15} />
                  <span>Replacement Truck for {selectedBreakdown.driver_vehicle_name}</span>
                </div>

                <div className="breakdown-target-summary">
                  <strong>Transfer Location:</strong>
                  <span>Breakdown GPS ({selectedBreakdown.location?.lat.toFixed(5)}, {selectedBreakdown.location?.lng.toFixed(5)})</span>
                  <strong>Original Destination:</strong>
                  <span>{selectedBreakdown.related_dispatch_details?.destination_name || 'Original Destination Depot'}</span>
                </div>

                {evaluatingReplacement ? (
                  <div className="evaluating-state">
                    <RefreshCw size={18} className="spin" />
                    <span>Evaluating nearest available replacement trucks via OSRM...</span>
                  </div>
                ) : replacementCandidates.length > 0 ? (
                  <div className="replacement-candidates-stack">
                    <span className="field-hint">Available Replacement Vehicles:</span>
                    {replacementCandidates.map((cand) => (
                      <div
                        key={cand.vehicle_id}
                        className={`candidate-card ${selectedReplacement?.vehicle_id === cand.vehicle_id ? 'selected' : ''}`}
                        onClick={() => setSelectedReplacement(cand)}
                      >
                        <div className="candidate-header">
                          <div>
                            <h4>{cand.vehicle_name} ({cand.number_plate})</h4>
                            <div className="driver-info-row">
                              <User size={13} />
                              <span>Driver: <strong>{cand.driver?.name}</strong></span>
                            </div>
                          </div>
                          <div className="metric-badge-inline">
                            <span>ETA: {cand.eta_min}m ({cand.distance_km}km)</span>
                          </div>
                        </div>
                      </div>
                    ))}

                    <button
                      type="button"
                      className="button button-primary dispatch-now-btn emergency-btn"
                      onClick={handleApproveRecovery}
                      disabled={isApprovingRecovery || !selectedReplacement}
                    >
                      {isApprovingRecovery ? (
                        <>
                          <RefreshCw size={16} className="spin" />
                          <span>Dispatching Replacement Truck...</span>
                        </>
                      ) : (
                        <>
                          <Send size={16} />
                          <span>APPROVE RECOVERY & DISPATCH REPLACEMENT</span>
                        </>
                      )}
                    </button>
                  </div>
                ) : (
                  <div className="diagnostics-panel">
                    <div className="diag-header">
                      <AlertCircle size={18} />
                      <strong>No Replacement Truck Available</strong>
                    </div>
                    <p className="diag-action">All compatible logistics trucks are currently assigned or off-duty. Escalate to regional supervisor.</p>
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {/* ════════════════════════════════════════════════════════════════════
            MODE 3: ACTIVE FLEET OPERATIONS
            ════════════════════════════════════════════════════════════════════ */}
        {dispatchMode === 'active' && (
          <div className="active-operations-stack">
            <div className="command-card">
              <div className="step-tag">
                <Radio size={15} />
                <span>Live Fleet Operations ({activeOperations.length})</span>
              </div>

              {activeOperations.length === 0 ? (
                <p className="placeholder-text">No logistics deliveries currently in transit.</p>
              ) : (
                <div className="active-ops-list">
                  {activeOperations.map((op) => (
                    <div key={op.id} className="active-op-card">
                      <div className="op-card-header">
                        <div>
                          <span className={`op-type-pill ${op.operation_type}`}>
                            {op.operation_type === 'EMERGENCY_REPLACEMENT' ? '🚨 RECOVERY OPERATION' : '📦 LOGISTICS DELIVERY'}
                          </span>
                          <strong className="op-title">{op.assigned_vehicle_name} ({op.assigned_vehicle_plate})</strong>
                          <span className="op-driver">Driver: {op.assigned_driver_name} ({op.assigned_driver_phone})</span>
                        </div>
                        <span className={`status-pill ${op.status.toLowerCase()}`}>
                          {op.status.replace(/_/g, ' ')}
                        </span>
                      </div>

                      {/* Route & Cargo details */}
                      <div className="op-route-meta">
                        <div>
                          <span className="meta-label">Route:</span>
                          <span className="meta-val">{op.location_name} → {op.destination_name}</span>
                        </div>
                        {op.cargo_description && (
                          <div>
                            <span className="meta-label">Cargo:</span>
                            <span className="meta-val">{op.cargo_description} ({op.cargo_weight_kg || '—'} kg)</span>
                          </div>
                        )}
                      </div>

                      {/* Progress Transitions */}
                      <div className="op-actions-bar">
                        {op.status === 'assigned' && (
                          <button className="stage-btn" onClick={() => handleAdvanceStatus(op.id, 'accepted')}>
                            Driver Accept
                          </button>
                        )}
                        {(op.status === 'assigned' || op.status === 'accepted') && (
                          <button
                            className="stage-btn"
                            onClick={() => handleAdvanceStatus(op.id, op.operation_type === 'EMERGENCY_REPLACEMENT' ? 'EN_ROUTE_TO_BREAKDOWN' : 'EN_ROUTE_TO_PICKUP')}
                          >
                            Mark En Route
                          </button>
                        )}
                        {(op.status === 'en_route' || op.status === 'EN_ROUTE_TO_PICKUP') && (
                          <button className="stage-btn" onClick={() => handleAdvanceStatus(op.id, 'AT_PICKUP')}>
                            At Pickup Site
                          </button>
                        )}
                        {op.status === 'AT_PICKUP' && (
                          <button className="stage-btn" onClick={() => handleAdvanceStatus(op.id, 'IN_TRANSIT')}>
                            Depart (In Transit)
                          </button>
                        )}
                        {op.status === 'EN_ROUTE_TO_BREAKDOWN' && (
                          <button className="stage-btn" onClick={() => handleAdvanceStatus(op.id, 'AT_BREAKDOWN_LOCATION')}>
                            At Breakdown Site
                          </button>
                        )}
                        {op.status === 'AT_BREAKDOWN_LOCATION' && (
                          <button className="stage-btn" onClick={() => handleAdvanceStatus(op.id, 'GOODS_TRANSFERRED')}>
                            Transfer Cargo Done
                          </button>
                        )}
                        {op.status === 'GOODS_TRANSFERRED' && (
                          <button className="stage-btn" onClick={() => handleAdvanceStatus(op.id, 'IN_TRANSIT_TO_DESTINATION')}>
                            Depart to Destination
                          </button>
                        )}
                        {(op.status === 'IN_TRANSIT' || op.status === 'IN_TRANSIT_TO_DESTINATION') && (
                          <button className="stage-btn complete" onClick={() => handleAdvanceStatus(op.id, 'completed')}>
                            Delivered / Completed
                          </button>
                        )}

                        {/* Breakdown Trigger Action */}
                        {op.operation_type === 'NORMAL_LOGISTICS' && op.status !== 'completed' && op.status !== 'VEHICLE_BREAKDOWN' && (
                          <button
                            className="stage-btn breakdown-trigger-btn"
                            title="Driver reports vehicle broke down mid-journey"
                            onClick={() => handleSimulateBreakdown(op.id)}
                          >
                            <AlertTriangle size={13} />
                            <span>Report Breakdown</span>
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </aside>

      {/* Right Map Canvas Shell */}
      <main className="dispatch-map-viewport">
        {/* Google Maps-style Location Search Box */}
        <div className="floating-map-search-container" ref={searchContainerRef}>
          <div className="search-input-shell">
            <Search size={18} className="search-icon" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onFocus={() => setShowSearchResults(true)}
              placeholder={`Search ${activeSearchTarget === 'pickup' ? 'Pickup Location' : 'Destination'} (Depots, Warehouses, Landmarks)...`}
              autoComplete="off"
            />
            {searchQuery && (
              <button
                type="button"
                className="clear-search-btn"
                onClick={() => {
                  setSearchQuery('');
                  setSearchResults(defaultLocations);
                }}
              >
                <X size={15} />
              </button>
            )}
          </div>

          {/* Quick Filter Categories */}
          <div className="quick-category-pills">
            {['warehouse', 'depot', 'bus_park', 'company_location', 'landmark'].map((cat) => (
              <button
                key={cat}
                type="button"
                className="category-pill"
                onClick={async () => {
                  setIsSearching(true);
                  try {
                    const res = await api.get(`/operational-locations/?category=${cat}`);
                    setSearchResults(res.data);
                    setShowSearchResults(true);
                  } finally {
                    setIsSearching(false);
                  }
                }}
              >
                <span>{cat.replace('_', ' ')}</span>
              </button>
            ))}
          </div>

          {/* Suggestions Dropdown */}
          {showSearchResults && (
            <div className="search-results-dropdown">
              {isSearching ? (
                <div className="dropdown-loading">
                  <RefreshCw size={16} className="spin" />
                  <span>Searching operational locations...</span>
                </div>
              ) : searchResults.length > 0 ? (
                <ul className="results-list">
                  {searchResults.map((loc) => (
                    <li
                      key={loc.id}
                      className="result-item"
                      onClick={() => handleSelectLocation(loc)}
                    >
                      <MapPin size={16} className="result-category-icon" />
                      <div className="result-text">
                        <strong>{loc.name}</strong>
                        <span className="result-addr">{loc.address}</span>
                      </div>
                      <span className="result-category-label">{loc.category}</span>
                    </li>
                  ))}
                </ul>
              ) : (
                <div className="dropdown-empty">
                  <span>No depot or operational location matching &quot;{searchQuery}&quot;.</span>
                  <button
                    type="button"
                    className="fallback-nominatim-btn"
                    onClick={async () => {
                      setIsSearching(true);
                      try {
                        const res = await fetch(`https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(searchQuery)}+Nepal&limit=5`);
                        const data = await res.json();
                        if (data && data.length > 0) {
                          const first = data[0];
                          handleSelectLocation({
                            id: 9999,
                            name: first.display_name.split(',')[0],
                            address: first.display_name,
                            lat: parseFloat(first.lat),
                            lng: parseFloat(first.lon),
                            category: 'landmark',
                          });
                        } else {
                          toast.error('Location not found.');
                        }
                      } finally {
                        setIsSearching(false);
                      }
                    }}
                  >
                    Search OpenStreetMap for &quot;{searchQuery}&quot;
                  </button>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Map Legend Overlay */}
        <div className="map-floating-legend">
          <span><MapPin size={13} /> Sarathi Fleet Operations</span>
          <div className="legend-items">
            <span className="legend-dot available" /> Available Truck
            <span className="legend-dot in-service" /> On Trip
            <span className="legend-dot pickup-legend" /> Pickup
            <span className="legend-dot dest-legend" /> Destination
            <span className="legend-dot breakdown-legend" /> Breakdown
          </div>
        </div>

        {/* Map Canvas */}
        <MapContainer
          center={NEPAL_CENTER}
          zoom={7}
          {...MAP_OPTIONS}
          style={{ width: '100%', height: '100%' }}
        >
          <TileLayer
            url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
            attribution='&copy; <a href="https://www.esri.com/">Esri</a>'
          />
          <GeoJSON data={NEPAL_GEOJSON as GeoJSON.GeoJsonObject} style={() => NEPAL_BORDER_STYLE} />

          <MapController flyTarget={flyTarget} />
          <MapClickHandler onMapClick={handleMapClick} />

          {/* Pickup Marker (Draggable) */}
          {pickupLocation && (
            <Marker
              position={[pickupLocation.lat, pickupLocation.lng]}
              icon={pickupMarkerIcon}
              draggable={true}
              eventHandlers={{
                dragend: (e) => {
                  const m = e.target as L.Marker;
                  const pos = m.getLatLng();
                  setPickupLocation(prev => prev ? ({ ...prev, lat: pos.lat, lng: pos.lng }) : null);
                },
              }}
            >
              <Popup>
                <div className="target-popup-content">
                  <strong>Pickup: {pickupLocation.name}</strong>
                  <p>{pickupLocation.address}</p>
                  <span className="coords">{pickupLocation.lat.toFixed(5)}, {pickupLocation.lng.toFixed(5)}</span>
                </div>
              </Popup>
            </Marker>
          )}

          {/* Destination Marker (Draggable) */}
          {destLocation && (
            <Marker
              position={[destLocation.lat, destLocation.lng]}
              icon={destMarkerIcon}
              draggable={true}
              eventHandlers={{
                dragend: (e) => {
                  const m = e.target as L.Marker;
                  const pos = m.getLatLng();
                  setDestLocation(prev => prev ? ({ ...prev, lat: pos.lat, lng: pos.lng }) : null);
                },
              }}
            >
              <Popup>
                <div className="target-popup-content">
                  <strong>Destination: {destLocation.name}</strong>
                  <p>{destLocation.address}</p>
                  <span className="coords">{destLocation.lat.toFixed(5)}, {destLocation.lng.toFixed(5)}</span>
                </div>
              </Popup>
            </Marker>
          )}

          {/* Breakdown Incident Markers */}
          {breakdownRequests.map((b) => {
            if (!b.location) return null;
            return (
              <Marker
                key={b.id}
                position={[b.location.lat, b.location.lng]}
                icon={breakdownMarkerIcon}
              >
                <Popup>
                  <div className="target-popup-content">
                    <strong>🚨 VEHICLE BREAKDOWN</strong>
                    <p>{b.driver_vehicle_name} ({b.driver_vehicle_plate})</p>
                    <p className="reason">{b.description}</p>
                    <span className="coords">{b.location.lat.toFixed(5)}, {b.location.lng.toFixed(5)}</span>
                  </div>
                </Popup>
              </Marker>
            );
          })}

          {/* Fleet Vehicles Markers */}
          {(vehiclesList.length > 0 ? vehiclesList : fleetVehicles).map((v) => {
            if (!v.location || !NEPAL_BOUNDS.contains([v.location.lat, v.location.lng])) return null;
            const isMatch = (selectedCandidate?.vehicle_id === v.id) || (selectedReplacement?.vehicle_id === v.id);
            const color = isMatch ? '#10b981' : v.is_available ? '#3b82f6' : '#9ca3af';

            return (
              <Marker
                key={v.id}
                position={[v.location.lat, v.location.lng]}
                icon={vehicleMarkerIcon(color, isMatch)}
              >
                <Popup>
                  <div className="vehicle-map-popup">
                    <strong>{v.name}</strong>
                    <span className="plate">{v.number_plate || 'No Plate'}</span>
                    <span className="type">{v.vehicle_type}</span>
                    <span className={`status ${v.is_available ? 'available' : 'busy'}`}>
                      {v.is_available ? 'Available for Operation' : 'On Active Trip'}
                    </span>
                    {v.driver_name && <span className="driver">Assigned Driver: {v.driver_name}</span>}
                  </div>
                </Popup>
              </Marker>
            );
          })}

          {/* Route Polyline (Candidate to Pickup) */}
          {(selectedCandidate?.route_geometry || recommended?.route_geometry) && (
            <Polyline
              positions={(selectedCandidate?.route_geometry || recommended?.route_geometry)!}
              pathOptions={{
                color: '#2563eb',
                weight: 5,
                opacity: 0.9,
                lineCap: 'round',
                lineJoin: 'round',
              }}
            />
          )}

          {/* Route Between Pickup and Destination */}
          {pickupLocation && destLocation && (
            <Polyline
              positions={[
                [pickupLocation.lat, pickupLocation.lng],
                [destLocation.lat, destLocation.lng],
              ]}
              pathOptions={{
                color: '#10b981',
                weight: 3,
                dashArray: '8, 8',
                opacity: 0.85,
              }}
            />
          )}

          {/* Breakdown Recovery Route (Replacement Vehicle to Breakdown Site) */}
          {selectedBreakdown?.location && selectedReplacement?.route_geometry && (
            <Polyline
              positions={selectedReplacement.route_geometry}
              pathOptions={{
                color: '#ef4444',
                weight: 5,
                opacity: 0.9,
                lineCap: 'round',
                lineJoin: 'round',
              }}
            />
          )}
        </MapContainer>
      </main>
    </div>
  );
}

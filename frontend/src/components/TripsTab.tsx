import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { MapContainer, TileLayer, Polyline, Marker, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { api } from '../api/auth';
import { toast } from './toast';
import {
  AlertCircle, History, MapPin, Pause, Play, RefreshCw,
  RotateCcw, Route, X,
} from 'lucide-react';

interface Trip {
  id: number;
  status: string;
  vehicle_name: string | null;
  vehicle_type: string | null;
  number_plate: string | null;
  driver_name: string | null;
  created_at: string;
  assigned_at: string | null;
  completed_at: string | null;
  distance_km: number | null;
  duration_min: number | null;
  trip_duration_seconds: number | null;
  request_lat: number;
  request_lng: number;
  point_count: number;
}

interface PlaybackPoint {
  lat: number;
  lng: number;
  speed_kmh: number;
  recorded_at: string;
}

interface PlaybackData {
  dispatch_id: number;
  status: string;
  vehicle_name: string | null;
  number_plate: string | null;
  request_lat: number;
  request_lng: number;
  points: PlaybackPoint[];
}

const STATUS_LABELS: Record<string, string> = {
  completed: 'Completed',
  cancelled: 'Cancelled',
  rejected: 'Rejected',
};

const formatDate = (value: string | null) => {
  if (!value) return '—';
  return new Date(value).toLocaleString(undefined, {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  });
};

const formatDuration = (seconds: number | null) => {
  if (seconds == null) return '—';
  if (seconds < 60) return `${seconds}s`;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return s ? `${m}m ${s}s` : `${m}m`;
};

const requestIcon = L.divIcon({
  className: '',
  html: `<div style="width:14px;height:14px;border-radius:50%;background:#f59e0b;border:3px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.4)"></div>`,
  iconSize: [14, 14],
  iconAnchor: [7, 7],
});

const vehicleIcon = L.divIcon({
  className: '',
  html: `<div style="width:16px;height:16px;border-radius:50%;background:#059669;border:3px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.4)"></div>`,
  iconSize: [16, 16],
  iconAnchor: [8, 8],
});

function FitBounds({ points }: { points: PlaybackPoint[] }) {
  const map = useMap();
  useEffect(() => {
    if (points.length) {
      map.fitBounds(
        L.latLngBounds(points.map(p => [p.lat, p.lng] as [number, number])),
        { padding: [48, 48], maxZoom: 15 }
      );
    }
  }, [map, points]);
  return null;
}

export default function TripsTab() {
  const [trips, setTrips] = useState<Trip[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [selected, setSelected] = useState<PlaybackData | null>(null);
  const [playbackLoading, setPlaybackLoading] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [speed, setSpeed] = useState(1);
  const timerRef = useRef<number | null>(null);

  const fetchTrips = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data } = await api.get<Trip[]>('/trips/');
      setTrips(data);
    } catch (err) {
      console.error('Failed to fetch trips', err);
      setError('Trip history could not be loaded. Please try again.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchTrips();
  }, [fetchTrips]);

  // Playback clock: advance the progress index while playing.
  useEffect(() => {
    if (timerRef.current !== null) {
      window.clearInterval(timerRef.current);
      timerRef.current = null;
    }
    if (playing && selected && selected.points.length) {
      timerRef.current = window.setInterval(() => {
        setProgress(previous => {
          const next = previous + 1;
          if (next >= selected.points.length - 1) {
            window.clearInterval(timerRef.current ?? undefined);
            timerRef.current = null;
            setPlaying(false);
            return selected.points.length - 1;
          }
          return next;
        });
      }, Math.round(400 / speed));
    }
    return () => {
      if (timerRef.current !== null) {
        window.clearInterval(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [playing, selected, speed]);

  const openReplay = async (trip: Trip) => {
    setPlaybackLoading(true);
    setPlaying(false);
    setProgress(0);
    try {
      const { data } = await api.get<PlaybackData>(`/trips/${trip.id}/playback/`);
      setSelected(data);
      setProgress(0);
      if (data.points.length > 1) {
        setPlaying(true);
      }
    } catch (err) {
      console.error('Failed to load playback', err);
      toast.error('Trip route could not be loaded.');
    } finally {
      setPlaybackLoading(false);
    }
  };

  const closeReplay = () => {
    setPlaying(false);
    setProgress(0);
    setSelected(null);
  };

  const traveled = useMemo(() => {
    if (!selected) return [];
    return selected.points.slice(0, progress + 1).map(p => [p.lat, p.lng] as [number, number]);
  }, [selected, progress]);

  const fullRoute = useMemo(() => {
    if (!selected) return [];
    return selected.points.map(p => [p.lat, p.lng] as [number, number]);
  }, [selected]);

  const currentPoint = selected?.points[Math.min(progress, selected.points.length - 1)];

  const elapsedSeconds = useMemo(() => {
    if (!selected || selected.points.length < 2) return 0;
    const start = new Date(selected.points[0].recorded_at).getTime();
    const end = new Date(selected.points[Math.min(progress, selected.points.length - 1)].recorded_at).getTime();
    return Math.max(0, Math.round((end - start) / 1000));
  }, [selected, progress]);

  const averageSpeed = useMemo(() => {
    if (!selected || selected.points.length === 0) return 0;
    const speeds = selected.points.map(p => p.speed_kmh).filter(s => s > 0);
    if (speeds.length === 0) return 0;
    return Math.round(speeds.reduce((a, b) => a + b, 0) / speeds.length);
  }, [selected]);

  if (error) {
    return (
      <section className="tab-content" aria-labelledby="trips-heading">
        <div className="page-heading">
          <div>
            <h2 id="trips-heading">Trip history</h2>
            <p>Replay recorded routes for finished trips.</p>
          </div>
        </div>
        <div className="inline-alert error" role="alert">
          <AlertCircle size={16} />
          <span>{error}</span>
          <button className="button button-secondary" style={{ marginLeft: 'auto' }} onClick={fetchTrips}>Retry</button>
        </div>
      </section>
    );
  }

  if (loading) {
    return (
      <section className="tab-content" aria-labelledby="trips-heading">
        <div className="page-heading">
          <div>
            <h2 id="trips-heading">Trip history</h2>
            <p>Replay recorded routes for finished trips.</p>
          </div>
        </div>
        <div className="list-skeleton">{[1, 2, 3].map(i => <div className="skeleton-row" key={i} />)}</div>
      </section>
    );
  }

  return (
    <section className="tab-content" aria-labelledby="trips-heading">
      <div className="page-heading">
        <div>
          <h2 id="trips-heading">Trip history</h2>
          <p>{trips.length} finished {trips.length === 1 ? 'trip' : 'trips'} · GPS breadcrumbs let you replay each route.</p>
        </div>
        <button className="button button-secondary" onClick={fetchTrips} title="Refresh trips">
          <RefreshCw size={16} />
          Refresh
        </button>
      </div>

      {trips.length === 0 ? (
        <div className="empty-state">
          <div>
            <div className="empty-icon"><History size={20} /></div>
            <h3>No trips yet</h3>
            <p>Finished dispatches will appear here once vehicles start recording GPS breadcrumbs while on a trip.</p>
          </div>
        </div>
      ) : (
        <div className="data-table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Vehicle</th>
                <th>Driver</th>
                <th>Status</th>
                <th>Date</th>
                <th>Distance</th>
                <th>Duration</th>
                <th>Points</th>
                <th style={{ textAlign: 'right' }}>Replay</th>
              </tr>
            </thead>
            <tbody>
              {trips.map(trip => (
                <tr key={trip.id}>
                  <td>
                    <div className="unit-row-main">
                      <strong>{trip.vehicle_name ?? 'Unknown'}</strong>
                      <span>{trip.number_plate ?? '—'}</span>
                    </div>
                  </td>
                  <td>{trip.driver_name ?? '—'}</td>
                  <td><span className={`status-badge ${trip.status === 'completed' ? 'available' : 'neutral'}`}><span>{STATUS_LABELS[trip.status] ?? trip.status}</span></span></td>
                  <td>{formatDate(trip.created_at)}</td>
                  <td>{trip.distance_km != null ? `${trip.distance_km} km` : '—'}</td>
                  <td>{formatDuration(trip.trip_duration_seconds)}</td>
                  <td>{trip.point_count}</td>
                  <td style={{ textAlign: 'right' }}>
                    <button
                      className="button button-secondary"
                      disabled={trip.point_count === 0}
                      title={trip.point_count === 0 ? 'No GPS breadcrumbs recorded for this trip' : 'Replay route'}
                      onClick={() => openReplay(trip)}
                    >
                      <Route size={15} />
                      Replay
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {selected && (
        <div className="modal-overlay" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) closeReplay(); }}>
          <div className="modal-content" style={{ width: 'min(920px, 100%)' }} role="dialog" aria-modal="true" aria-labelledby="playback-title">
            <div className="modal-header">
              <div>
                <span>Route playback</span>
                <h2 id="playback-title">{selected.vehicle_name} · {selected.number_plate ?? 'Trip #' + selected.dispatch_id}</h2>
              </div>
              <button className="icon-button" onClick={closeReplay} aria-label="Close playback"><X size={17} /></button>
            </div>

            <div className="modal-body">
              {playbackLoading ? (
                <div className="list-skeleton">{[1, 2].map(i => <div className="skeleton-row" key={i} />)}</div>
              ) : selected.points.length === 0 ? (
                <div className="empty-state">
                  <div>
                    <div className="empty-icon"><MapPin size={20} /></div>
                    <h3>No recorded route</h3>
                    <p>This trip finished before GPS breadcrumb recording was enabled, so there is nothing to replay.</p>
                  </div>
                </div>
              ) : (
                <>
                  <div className="playback-map" style={{ height: 380, borderRadius: 8, overflow: 'hidden', border: '1px solid var(--surface-border)' }}>
                    <MapContainer center={[currentPoint?.lat ?? 26.65, currentPoint?.lng ?? 87.89]} zoom={13} style={{ width: '100%', height: '100%' }}>
                      <TileLayer url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}" attribution='&copy; <a href="https://www.esri.com/en-us/home">Esri</a>' />
                      <FitBounds points={selected.points} />
                      <Polyline positions={fullRoute} pathOptions={{ color: '#94a3b8', weight: 4, opacity: 0.35, dashArray: '4 6' }} />
                      {traveled.length > 1 && <Polyline positions={traveled} pathOptions={{ color: '#059669', weight: 4, opacity: 0.9, lineCap: 'round', lineJoin: 'round' }} />}
                      <Marker position={[selected.request_lat, selected.request_lng]} icon={requestIcon} />
                      {currentPoint && <Marker position={[currentPoint.lat, currentPoint.lng]} icon={vehicleIcon} />}
                    </MapContainer>
                  </div>

                  <div className="playback-controls" style={{ marginTop: 14 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
                      <button className="button button-primary" style={{ padding: '8px 14px' }} onClick={() => setPlaying(p => !p)}>
                        {playing ? <><Pause size={16} />Pause</> : <><Play size={16} />Play</>}
                      </button>
                      <button className="button button-secondary" style={{ padding: '8px 14px' }} onClick={() => { setProgress(0); setPlaying(true); }} title="Restart">
                        <RotateCcw size={16} />
                        Restart
                      </button>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginLeft: 4 }}>
                        <span style={{ fontSize: '.65rem', color: 'var(--text-muted)' }}>Speed</span>
                        {[1, 2, 4].map(s => (
                          <button key={s} className={`button ${speed === s ? 'button-primary' : 'button-secondary'}`} style={{ padding: '6px 10px', fontSize: '.68rem' }} onClick={() => setSpeed(s)}>{s}×</button>
                        ))}
                      </div>
                      <div style={{ marginLeft: 'auto', textAlign: 'right' }}>
                        <div style={{ fontSize: '.75rem', fontWeight: 700 }}>{progress} / {selected.points.length - 1} points</div>
                        <div style={{ fontSize: '.63rem', color: 'var(--text-muted)' }}>{currentPoint ? `@ ${currentPoint.speed_kmh} km/h` : '—'}</div>
                      </div>
                    </div>
                    <input
                      type="range"
                      min={0}
                      max={Math.max(0, selected.points.length - 1)}
                      value={progress}
                      onChange={event => { setProgress(Number(event.target.value)); }}
                      style={{ width: '100%', marginTop: 12, accentColor: 'var(--accent)' }}
                      aria-label="Playback scrubber"
                    />
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 10, marginTop: 16 }}>
                    <div className="result-metrics" style={{ gridTemplateColumns: '1fr', gap: 6, marginTop: 0 }}>
                      <div><span>Elapsed</span><strong>{formatDuration(elapsedSeconds)}</strong></div>
                    </div>
                    <div className="result-metrics" style={{ gridTemplateColumns: '1fr', gap: 6, marginTop: 0 }}>
                      <div><span>Avg speed</span><strong>{averageSpeed} km/h</strong></div>
                    </div>
                    <div className="result-metrics" style={{ gridTemplateColumns: '1fr', gap: 6, marginTop: 0 }}>
                      <div><span>Breadcrumbs</span><strong>{selected.points.length}</strong></div>
                    </div>
                    <div className="result-metrics" style={{ gridTemplateColumns: '1fr', gap: 6, marginTop: 0 }}>
                      <div><span>Status</span><strong>{STATUS_LABELS[selected.status] ?? selected.status}</strong></div>
                    </div>
                  </div>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

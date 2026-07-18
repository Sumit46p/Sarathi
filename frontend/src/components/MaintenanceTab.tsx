import { useState, useEffect, useCallback } from 'react';
import { api } from '../api/auth';
import { AlertCircle, Plus, Search, Trash2, Truck, Wrench, X } from 'lucide-react';
import { MapContainer, Marker, Popup, TileLayer, useMap } from 'react-leaflet';
import L from 'leaflet';

interface MaintenanceRecord {
  id: number;
  vehicle: number;
  vehicle_name: string;
  maintenance_type: string;
  description: string;
  due_date: string;
  completed: boolean;
  completed_at: string | null;
  owner: number;
  is_overdue: boolean;
}

const NEPAL_BOUNDS = L.latLngBounds([26.347, 80.058], [30.447, 88.201]);
const MAP_OPTIONS = {
  maxBounds: NEPAL_BOUNDS,
  maxBoundsViscosity: 1,
  minZoom: 7,
} as const;

function MapController({ center }: { center: [number, number] | null }) {
  const map = useMap();
  useEffect(() => {
    if (center && NEPAL_BOUNDS.contains(center)) map.setView(center, 14, { animate: true, duration: 0.7 });
  }, [center, map]);
  return null;
}

export default function MaintenanceTab() {
  const [records, setRecords] = useState<MaintenanceRecord[]>([]);
  const [upcoming, setUpcoming] = useState<MaintenanceRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [vehicles, setVehicles] = useState<{id: number, name: string}[]>([]);
  const [showAddModal, setShowAddModal] = useState(false);
  const [newRecord, setNewRecord] = useState({
    vehicle: '',
    maintenance_type: 'oil_change',
    due_date: new Date().toISOString().split('T')[0],
    description: '',
  });
  const [addLoading, setAddLoading] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const fetchMaintenance = useCallback(async () => {
    try {
      const [recordsRes, upcomingRes, vehiclesRes] = await Promise.all([
        api.get('/maintenance/'),
        api.get('/maintenance/upcoming/'),
        api.get('/vehicles/')
      ]);
      setRecords(recordsRes.data);
      setUpcoming(upcomingRes.data);
      setVehicles(vehiclesRes.data);
    } catch (error) {
      console.error('Failed to fetch maintenance data', error);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchMaintenance();
  }, [fetchMaintenance]);

  const handleAddRecord = async () => {
    if (!newRecord.vehicle) return;
    setAddLoading(true);
    setFormError(null);
    try {
      await api.post('/maintenance/', newRecord);
      setShowAddModal(false);
      setNewRecord({
        vehicle: '',
        maintenance_type: 'oil_change',
        due_date: new Date().toISOString().split('T')[0],
        description: '',
      });
      await fetchMaintenance();
    } catch (error) {
      console.error('Failed to add maintenance record', error);
      setFormError('Failed to create maintenance record. Please check your input and try again.');
    } finally {
      setAddLoading(false);
    }
  };

  const handleDeleteRecord = async (id: number) => {
    if (!window.confirm('Delete this maintenance record? This action cannot be undone.')) return;
    try {
      await api.delete(`/maintenance/${id}/`);
      await fetchMaintenance();
    } catch (error) {
      console.error('Failed to delete maintenance record', error);
      setFormError('Failed to delete maintenance record.');
    }
  };

  if (loading) return <div>Loading...</div>;

  return (
    <section className="tab-content">
      <div className="page-heading">
        <div>
          <h2>Vehicle maintenance</h2>
          <p>Track service history and upcoming appointments.</p>
        </div>
        <button className="button button-primary" onClick={() => { setFormError(null); setShowAddModal(true); }}><Plus size={16} />Add record</button>
      </div>
      
      <div className="map-container">
        <MapContainer center={[28.2, 84.0]} zoom={7} {...MAP_OPTIONS} style={{ width: '100%', height: '400px' }}>
          <TileLayer url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}" />
          <Marker position={[30.198, 81.036]}><Popup>Lipulekh Pass</Popup></Marker>
          <Marker position={[30.183, 80.950]}><Popup>Limpiyadhura</Popup></Marker>
        </MapContainer>
      </div>
      
      {upcoming.length > 0 && (
        <div className="upcoming-alerts">
          <h3>Upcoming service</h3>
          {upcoming.map(rec => (
            <div key={rec.id} className={`alert-row ${rec.is_overdue ? 'overdue' : ''}`}>
              <Wrench size={16} /> {rec.vehicle_name} due for {rec.maintenance_type.replace('_', ' ')} on {rec.due_date}
            </div>
          ))}
        </div>
      )}

      <div className="data-table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Vehicle</th>
              <th>Service</th>
              <th>Date</th>
              <th>Next Due</th>
              <th><span className="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            {records.map(rec => (
              <tr key={rec.id} className={rec.is_overdue ? 'overdue' : ''}>
                <td>{rec.vehicle_name}</td>
                <td>{rec.maintenance_type.replace('_', ' ')}</td>
                <td>{rec.due_date}</td>
                <td>{rec.completed ? 'Completed' : 'Pending'}</td>
                <td><button className="icon-button danger" onClick={() => handleDeleteRecord(rec.id)} title="Delete record" aria-label={`Delete ${rec.vehicle_name} record`}><Trash2 size={15} /></button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {showAddModal && (
        <div className="modal-overlay" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setShowAddModal(false); }}>
          <div className="modal-content" role="dialog" aria-modal="true" aria-labelledby="record-modal-title">
            <div className="modal-header">
              <div>
                <span>Maintenance records</span>
                <h2 id="record-modal-title">Add service record</h2>
              </div>
              <button className="icon-button" onClick={() => setShowAddModal(false)} aria-label="Close form"><X size={17} /></button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <label htmlFor="vehicle-select">Vehicle</label>
                <select id="vehicle-select" className="input-field" value={newRecord.vehicle} onChange={event => setNewRecord({ ...newRecord, vehicle: event.target.value })} required>
                  <option value="">Select a vehicle</option>
                  {vehicles.map(v => <option key={v.id} value={v.id}>{v.name}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label htmlFor="service-type">Service type</label>
                <select id="service-type" className="input-field" value={newRecord.maintenance_type} onChange={event => setNewRecord({ ...newRecord, maintenance_type: event.target.value })}>
                  <option value="oil_change">Oil Change</option>
                  <option value="tire_rotation">Tire Rotation</option>
                  <option value="inspection">Inspection</option>
                  <option value="repair">Repair</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div className="form-group">
                <label htmlFor="due-date">Due date</label>
                <input id="due-date" type="date" className="input-field" value={newRecord.due_date} onChange={event => setNewRecord({ ...newRecord, due_date: event.target.value })} required />
              </div>
              <div className="form-group">
                <label htmlFor="description">Description</label>
                <textarea id="description" className="input-field" value={newRecord.description} onChange={event => setNewRecord({ ...newRecord, description: event.target.value })} rows={3} />
              </div>
              {formError && <div className="inline-alert error"><AlertCircle size={16} />{formError}</div>}
            </div>
            <div className="modal-footer">
              <button className="button button-secondary" onClick={() => setShowAddModal(false)}>Cancel</button>
              <button className="button button-primary" onClick={handleAddRecord} disabled={!newRecord.vehicle || addLoading}>{addLoading ? 'Adding...' : 'Add record'}</button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

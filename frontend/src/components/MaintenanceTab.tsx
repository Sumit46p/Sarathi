import { useState, useEffect, useCallback, useMemo } from 'react';
import { api } from '../api/auth';
import { AlertCircle, CheckCircle2, Plus, Search, Trash2, Truck, Wrench, X } from 'lucide-react';
import { toast } from './toast';

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

const MAINTENANCE_TYPES = [
  { value: 'oil_change', label: 'Oil Change' },
  { value: 'tire_rotation', label: 'Tire Rotation' },
  { value: 'inspection', label: 'Inspection' },
  { value: 'repair', label: 'Repair' },
  { value: 'other', label: 'Other' },
];

const formatType = (value: string) => {
  const found = MAINTENANCE_TYPES.find(t => t.value === value);
  return found ? found.label : value.replace(/_/g, ' ');
};

export default function MaintenanceTab() {
  const [records, setRecords] = useState<MaintenanceRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [dataError, setDataError] = useState<string | null>(null);
  const [vehicles, setVehicles] = useState<{ id: number; name: string }[]>([]);
  const [showAddModal, setShowAddModal] = useState(false);
  const [newRecord, setNewRecord] = useState({
    vehicle: '',
    maintenance_type: 'oil_change',
    due_date: new Date().toISOString().split('T')[0],
    description: '',
  });
  const [addLoading, setAddLoading] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [vehicleFilter, setVehicleFilter] = useState('all');
  const [completingId, setCompletingId] = useState<number | null>(null);

  const fetchMaintenance = useCallback(async () => {
    try {
      const [recordsRes, vehiclesRes] = await Promise.all([
        api.get('/maintenance/'),
        api.get('/vehicles/'),
      ]);
      setRecords(recordsRes.data);
      setVehicles(vehiclesRes.data);
      setDataError(null);
    } catch (error) {
      console.error('Failed to fetch maintenance data', error);
      setDataError('Maintenance data could not be refreshed.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
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
      toast.success('Maintenance record added');
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
      toast.success('Record deleted');
    } catch (error) {
      console.error('Failed to delete maintenance record', error);
      setDataError('Failed to delete maintenance record.');
      toast.error('Failed to delete maintenance record.');
    }
  };

  const handleMarkComplete = async (id: number) => {
    setCompletingId(id);
    try {
      await api.patch(`/maintenance/${id}/`, { completed: true });
      await fetchMaintenance();
      toast.success('Marked complete');
    } catch (error) {
      console.error('Failed to mark record complete', error);
      setDataError('Could not update maintenance record.');
      toast.error('Could not update maintenance record.');
    } finally {
      setCompletingId(null);
    }
  };

  const groupedRecords = useMemo(() => {
    const filtered = records.filter(r => {
      const matchesQuery = !query.trim() || 
        r.vehicle_name.toLowerCase().includes(query.toLowerCase()) ||
        formatType(r.maintenance_type).toLowerCase().includes(query.toLowerCase());
      const matchesVehicle = vehicleFilter === 'all' || r.vehicle === Number(vehicleFilter);
      return matchesQuery && matchesVehicle;
    });

    const groups: Record<string, MaintenanceRecord[]> = {};
    for (const r of filtered) {
      if (!groups[r.vehicle_name]) groups[r.vehicle_name] = [];
      groups[r.vehicle_name].push(r);
    }
    return groups;
  }, [records, query, vehicleFilter]);

  const overdueCount = records.filter(r => r.is_overdue).length;
  const pendingCount = records.filter(r => !r.completed).length;

  if (loading) return (
    <section className="tab-content">
      <div className="list-skeleton">{[1, 2, 3].map(i => <div className="skeleton-row" key={i} />)}</div>
    </section>
  );

  const vehicleOptions = [
    { value: 'all', label: 'All vehicles' },
    ...vehicles.map(v => ({ value: String(v.id), label: v.name })),
  ];

  return (
    <section className="tab-content" aria-labelledby="maintenance-heading">
      <div className="page-heading">
        <div>
          <h2 id="maintenance-heading">Vehicle maintenance</h2>
          <p>Track service history and upcoming appointments.</p>
        </div>
        <button className="button button-primary" onClick={() => { setFormError(null); setShowAddModal(true); }}>
          <Plus size={16} />Add record
        </button>
      </div>

      {/* Summary metrics */}
      <div className="metrics-grid" style={{ marginBottom: 20 }}>
        <article className="metric-card">
          <div className="metric-heading"><span>Total records</span><Wrench size={17} /></div>
          <strong>{records.length}</strong>
          <p>All maintenance entries</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Pending</span><AlertCircle size={17} /></div>
          <strong>{pendingCount}</strong>
          <p>Not yet completed</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Overdue</span><AlertCircle size={17} /></div>
          <strong style={{ color: overdueCount > 0 ? 'var(--danger)' : undefined }}>{overdueCount}</strong>
          <p style={{ color: overdueCount > 0 ? 'var(--danger)' : undefined }}>Past due date</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Completed</span><CheckCircle2 size={17} /></div>
          <strong>{records.filter(r => r.completed).length}</strong>
          <p>All caught up</p>
        </article>
      </div>

      {dataError && (
        <div className="global-alert" role="alert" style={{ marginBottom: 16, borderRadius: 7 }}>
          <AlertCircle size={16} /><span>{dataError}</span>
          <button onClick={() => setDataError(null)} aria-label="Dismiss"><X size={15} /></button>
        </div>
      )}

      {/* Toolbar */}
      <div className="section-toolbar">
        <div>
          <h2>All records</h2>
          <span>{records.length} entries</span>
        </div>
        <div className="toolbar-controls">
          <select
            className="input-field"
            style={{ width: 160, minHeight: 36, fontSize: '.78rem' }}
            value={vehicleFilter}
            onChange={e => setVehicleFilter(e.target.value)}
            aria-label="Filter by vehicle"
          >
            {vehicleOptions.map(o => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
          <div className="search-field">
            <Search size={15} />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Search records"
              aria-label="Search maintenance records"
            />
          </div>
        </div>
      </div>

      {Object.keys(groupedRecords).length === 0 ? (
        <div className="empty-state">
          <div className="empty-icon"><Wrench size={20} /></div>
          <h3>No maintenance records</h3>
          <p>Add your first maintenance record to start tracking vehicle service schedules.</p>
        </div>
      ) : (
        <div className="data-table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Vehicle</th>
                <th>Service</th>
                <th>Due date</th>
                <th>Status</th>
                <th><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              {Object.entries(groupedRecords).map(([vehicleName, vehicleRecords]) =>
                vehicleRecords.map((rec, idx) => (
                  <tr key={rec.id} className={rec.is_overdue ? 'overdue-row' : ''}>
                    {idx === 0 && <td rowSpan={vehicleRecords.length}>
                      <div className="primary-cell">
                        <div className="entity-icon"><Truck size={17} /></div>
                        <div><strong>{vehicleName}</strong></div>
                      </div>
                    </td>}
                    <td><span>{formatType(rec.maintenance_type)}</span>{rec.description ? <span className="muted" style={{ display: 'block', fontSize: '.65rem', marginTop: 2 }}>{rec.description}</span> : null}</td>
                    <td><span className={rec.is_overdue ? 'overdue-date' : ''}>{rec.due_date}</span></td>
                    <td>
                      {rec.completed ? (
                        <span className="status-badge available"><span />Completed</span>
                      ) : rec.is_overdue ? (
                        <span className="status-badge unavailable"><span />Overdue</span>
                      ) : (
                        <span className="status-badge neutral"><span />Pending</span>
                      )}
                    </td>
                    <td>
                      <div className="row-actions">
                        {!rec.completed && (
                          <button
                            className="button button-primary"
                            style={{ minHeight: 30, padding: '4px 10px', fontSize: '.7rem' }}
                            onClick={() => handleMarkComplete(rec.id)}
                            disabled={completingId === rec.id}
                          >
                            {completingId === rec.id ? '...' : <CheckCircle2 size={13} />}
                            Mark done
                          </button>
                        )}
                        <button
                          className="icon-button danger"
                          onClick={() => handleDeleteRecord(rec.id)}
                          title="Delete record"
                          aria-label={`Delete ${vehicleName} record`}
                        >
                          <Trash2 size={15} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* Add modal */}
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
                  {MAINTENANCE_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label htmlFor="due-date">Due date</label>
                <input id="due-date" type="date" className="input-field" value={newRecord.due_date} onChange={event => setNewRecord({ ...newRecord, due_date: event.target.value })} required />
              </div>
              <div className="form-group">
                <label htmlFor="description">Description <span className="muted">(optional)</span></label>
                <textarea id="description" className="input-field" value={newRecord.description} onChange={event => setNewRecord({ ...newRecord, description: event.target.value })} rows={3} placeholder="Brief details about the service needed..." />
              </div>
              {formError && <div className="inline-alert error"><AlertCircle size={16} />{formError}</div>}
            </div>
            <div className="modal-footer">
              <button className="button button-secondary" onClick={() => setShowAddModal(false)}>Cancel</button>
              <button className="button button-primary" onClick={handleAddRecord} disabled={!newRecord.vehicle || addLoading}>
                {addLoading ? 'Adding...' : 'Add record'}
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

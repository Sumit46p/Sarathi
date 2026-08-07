import { useEffect, useMemo, useState } from 'react';
import {
  AlertCircle, CalendarClock, Fuel, Receipt, RefreshCw,
  Search, Truck, Wallet, X,
} from 'lucide-react';
import { api } from '../api/auth';

interface FuelLog {
  id: number;
  vehicle: number;
  vehicle_name: string;
  driver: number;
  driver_name: string;
  fuel_type?: string;
  liters?: string;
  amount: string;
  cost_per_liter?: string;
  odometer_reading: string | null;
  receipt_image_url: string | null;
  notes: string | null;
  created_at: string;
}

interface VehicleOption {
  id: number;
  name: string;
}

export default function FuelTab() {
  const [logs, setLogs] = useState<FuelLog[]>([]);
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [dataError, setDataError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [vehicleFilter, setVehicleFilter] = useState('all');
  const [preview, setPreview] = useState<{ url: string; label: string } | null>(null);

  const fetchData = async () => {
    setLoading(true);
    setDataError(null);
    try {
      const [logsRes, vehiclesRes] = await Promise.all([
        api.get('/fuel-logs/'),
        api.get('/vehicles/'),
      ]);
      setLogs(logsRes.data);
      setVehicles(vehiclesRes.data);
    } catch (error: any) {
      console.error('Failed to fetch fuel data', error);
      setDataError('Fuel data could not be refreshed.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    fetchData();
  }, []);

  const filteredLogs = useMemo(() => {
    const s = query.toLowerCase();
    return logs.filter((log) => {
      const matchesVehicle = vehicleFilter === 'all' || String(log.vehicle) === vehicleFilter;
      const matchesQuery =
        log.vehicle_name.toLowerCase().includes(s) ||
        log.driver_name.toLowerCase().includes(s);
      return matchesVehicle && matchesQuery;
    });
  }, [logs, query, vehicleFilter]);

  const stats = useMemo(() => {
    const totalCost = logs.reduce((sum, log) => sum + Number(log.amount || 0), 0);
    const now = new Date();
    const monthCost = logs
      .filter((log) => {
        const d = new Date(log.created_at);
        return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
      })
      .reduce((sum, log) => sum + Number(log.amount || 0), 0);
    const vehiclesCount = new Set(logs.map((log) => log.vehicle_name)).size;
    const avgCost = logs.length > 0 ? totalCost / logs.length : 0;
    return { totalCost, monthCost, vehiclesCount, avgCost };
  }, [logs]);

  const formatNPR = (value: number) =>
    `रु ${value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

  const formatDate = (iso: string) =>
    new Date(iso).toLocaleString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    });

  return (
    <section className="tab-content" aria-labelledby="fuel-heading">
      <div className="page-heading">
        <div>
          <h2 id="fuel-heading">Fuel management</h2>
          <p>Track fleet fuel consumption and costs with receipt proof.</p>
        </div>
        <button className="button button-primary" onClick={fetchData} disabled={loading}>
          {loading ? <RefreshCw size={15} className="spin" /> : <RefreshCw size={15} />}
          Refresh
        </button>
      </div>

      {/* Summary metrics */}
      <div className="metrics-grid stagger" style={{ marginBottom: 20 }}>
        <article className="metric-card">
          <div className="metric-heading"><span>Total entries</span><Fuel size={17} /></div>
          <strong>{logs.length}</strong>
          <p>All fuel expenses logged</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Total cost</span><Wallet size={17} /></div>
          <strong>{formatNPR(stats.totalCost)}</strong>
          <p>Across all vehicles</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>This month</span><CalendarClock size={17} /></div>
          <strong>{formatNPR(stats.monthCost)}</strong>
          <p>Fuel cost in current month</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Vehicles</span><Truck size={17} /></div>
          <strong>{stats.vehiclesCount}</strong>
          <p>Distinct vehicles fuelled</p>
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
          <h2>Fuel records</h2>
          <span>{filteredLogs.length} of {logs.length} entries</span>
        </div>
        <div className="toolbar-controls">
          <select
            className="input-field"
            style={{ width: 160, minHeight: 36, fontSize: '.78rem' }}
            value={vehicleFilter}
            onChange={e => setVehicleFilter(e.target.value)}
            aria-label="Filter by vehicle"
          >
            <option value="all">All vehicles</option>
            {vehicles.map(v => (
              <option key={v.id} value={v.id}>{v.name}</option>
            ))}
          </select>
          <div className="search-field">
            <Search size={15} />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Search vehicle or driver"
              aria-label="Search fuel records"
            />
          </div>
        </div>
      </div>

      {loading ? (
        <div className="list-skeleton" aria-label="Loading fuel records">
          <div className="skeleton-row" />
          <div className="skeleton-row" />
          <div className="skeleton-row" />
          <div className="skeleton-row" />
        </div>
      ) : filteredLogs.length === 0 ? (
        <div className="empty-state">
          <div className="empty-icon"><Fuel size={20} /></div>
          <h3>{logs.length === 0 ? 'No fuel records yet' : 'No matching fuel records'}</h3>
          <p>
            {logs.length === 0
              ? 'Fuel entries logged from the driver app will appear here with receipt proof.'
              : 'Try adjusting your search or vehicle filter.'}
          </p>
        </div>
      ) : (
        <div className="data-table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Vehicle</th>
                <th>Driver</th>
                <th>Fuel Type</th>
                <th style={{ textAlign: 'right' }}>Liters</th>
                <th>Date & time</th>
                <th style={{ textAlign: 'right' }}>Amount</th>
                <th style={{ textAlign: 'right' }}>Odometer</th>
                <th>Receipt</th>
              </tr>
            </thead>
            <tbody>
              {filteredLogs.map((log) => (
                <tr key={log.id}>
                  <td>
                    <div className="primary-cell">
                      <div className="entity-icon"><Truck size={17} /></div>
                      <div><strong>{log.vehicle_name}</strong></div>
                    </div>
                  </td>
                  <td><span>{log.driver_name}</span></td>
                  <td><span style={{ textTransform: 'capitalize' }}>{log.fuel_type || '—'}</span></td>
                  <td>
                    <div style={{ display: 'flex', justifyContent: 'flex-end', color: 'var(--text-muted)' }}>
                      {log.liters ? `${log.liters}L` : '—'}
                    </div>
                  </td>
                  <td><span>{formatDate(log.created_at)}</span></td>
                  <td>
                    <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
                      <span className="status-badge available"><span />{formatNPR(Number(log.amount || 0))}</span>
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', justifyContent: 'flex-end', color: 'var(--text-muted)' }}>
                      {log.odometer_reading != null ? `${log.odometer_reading} km` : '—'}
                    </div>
                  </td>
                  <td>
                    {log.receipt_image_url ? (
                      <button
                        className="issue-photo-thumb"
                        onClick={() => setPreview({ url: log.receipt_image_url!, label: `${log.vehicle_name} receipt` })}
                        title="View receipt"
                        aria-label={`View receipt for ${log.vehicle_name}`}
                      >
                        <img src={log.receipt_image_url} alt={`Receipt for ${log.vehicle_name}`} />
                      </button>
                    ) : (
                      <span className="status-badge unavailable"><span />No receipt</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Receipt preview modal */}
      {preview && (
        <div
          className="modal-overlay"
          role="presentation"
          onMouseDown={event => {
            if (event.target === event.currentTarget) setPreview(null);
          }}
        >
          <div className="modal-content" role="dialog" aria-modal="true" aria-labelledby="receipt-modal-title">
            <div className="modal-header">
              <div>
                <span>Fuel receipt</span>
                <h2 id="receipt-modal-title">{preview.label}</h2>
              </div>
              <button className="icon-button" onClick={() => setPreview(null)} aria-label="Close preview"><X size={17} /></button>
            </div>
            <div className="modal-body" style={{ display: 'grid', placeItems: 'center', background: 'var(--bg-tertiary)' }}>
              <img
                src={preview.url}
                alt={preview.label}
                style={{
                  maxWidth: '100%',
                  maxHeight: '60vh',
                  objectFit: 'contain',
                  borderRadius: 7,
                  boxShadow: 'var(--shadow-md)',
                }}
              />
            </div>
            <div className="modal-footer">
              <button className="button button-secondary" onClick={() => setPreview(null)}>Close</button>
              <a className="button button-primary" href={preview.url} target="_blank" rel="noreferrer">
                <Receipt size={15} />Open original
              </a>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
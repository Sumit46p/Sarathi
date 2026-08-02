import { useState, useEffect, useCallback } from 'react';
import { api } from '../api/auth';
import { AlertCircle, Droplets, RefreshCw, Search, Truck, UserRound, X } from 'lucide-react';

interface FuelEntry {
  id: number;
  vehicle_name: string;
  driver_name: string;
  liters: string;
  cost_per_liter: string;
  total_cost: string;
  odometer_km: string | null;
  notes: string | null;
  fueled_at: string;
}

export default function FuelTab() {
  const [entries, setEntries] = useState<FuelEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [dataError, setDataError] = useState<string | null>(null);
  const [query, setQuery] = useState('');

  const fetchEntries = useCallback(async () => {
    try {
      setLoading(true);
      setDataError(null);
      const res = await api.get('/fuel/');
      setEntries(res.data);
    } catch (err: any) {
      setDataError(err.response?.data?.error || 'Fuel data could not be refreshed.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchEntries();
  }, [fetchEntries]);

  const filtered = entries.filter(e => {
    const s = query.toLowerCase();
    return (
      e.vehicle_name.toLowerCase().includes(s) ||
      e.driver_name.toLowerCase().includes(s)
    );
  });

  // Summary metrics
  const totalLiters = entries.reduce((sum, e) => sum + parseFloat(e.liters), 0);
  const totalCost   = entries.reduce((sum, e) => sum + parseFloat(e.total_cost), 0);
  const avgCostPerL = totalLiters > 0 ? totalCost / totalLiters : 0;

  if (loading) return (
    <section className="tab-content">
      <div className="list-skeleton">{[1, 2, 3].map(i => <div className="skeleton-row" key={i} />)}</div>
    </section>
  );

  return (
    <section className="tab-content" aria-labelledby="fuel-heading">
      <div className="page-heading">
        <div>
          <h2 id="fuel-heading">Fuel management</h2>
          <p>Track fleet fuel consumption and costs across all drivers.</p>
        </div>
        <button
          className="button button-secondary"
          onClick={fetchEntries}
          disabled={loading}
          title="Refresh fuel entries"
        >
          <RefreshCw size={15} className={loading ? 'spin' : ''} />
          Refresh
        </button>
      </div>

      {/* Summary metrics */}
      <div className="metrics-grid" style={{ marginBottom: 20 }}>
        <article className="metric-card">
          <div className="metric-heading"><span>Total fill-ups</span><Droplets size={17} /></div>
          <strong>{entries.length}</strong>
          <p>All fuel entries</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Total liters</span><Droplets size={17} /></div>
          <strong>{totalLiters.toFixed(1)} L</strong>
          <p>Across all vehicles</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Total cost</span><Truck size={17} /></div>
          <strong>रु {totalCost.toLocaleString()}</strong>
          <p>All fuel expenses</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Avg cost / liter</span><Droplets size={17} /></div>
          <strong>रु {avgCostPerL.toFixed(2)}</strong>
          <p>Fleet average</p>
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
          <span>{filtered.length} entr{filtered.length === 1 ? 'y' : 'ies'}</span>
        </div>
        <div className="toolbar-controls">
          <div className="search-field">
            <Search size={15} />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Search vehicle or driver…"
              aria-label="Search fuel entries"
            />
          </div>
        </div>
      </div>

      {/* Table or empty state */}
      {filtered.length === 0 ? (
        <div className="empty-state">
          <div className="empty-icon"><Droplets size={20} /></div>
          <h3>No fuel records found</h3>
          <p>
            {entries.length === 0
              ? 'No fuel entries have been submitted yet. Drivers can log fuel from the mobile app.'
              : 'No entries match your search.'}
          </p>
        </div>
      ) : (
        <div className="data-table-wrap">
          <table className="data-table" aria-label="Fuel entries">
            <thead>
              <tr>
                <th>Vehicle</th>
                <th>Driver</th>
                <th>Date &amp; Time</th>
                <th>Liters</th>
                <th>Cost / L</th>
                <th>Total Cost</th>
                <th>Odometer</th>
                <th>Notes</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(entry => (
                <tr key={entry.id}>
                  <td>
                    <div className="primary-cell">
                      <div className="entity-icon"><Truck size={17} /></div>
                      <div><strong>{entry.vehicle_name}</strong></div>
                    </div>
                  </td>
                  <td>
                    <div className="primary-cell">
                      <div className="entity-icon"><UserRound size={15} /></div>
                      <div>{entry.driver_name}</div>
                    </div>
                  </td>
                  <td>
                    {new Date(entry.fueled_at).toLocaleString(undefined, {
                      month: 'short', day: 'numeric',
                      hour: 'numeric', minute: '2-digit',
                    })}
                  </td>
                  <td>{parseFloat(entry.liters).toFixed(2)} L</td>
                  <td>रु {parseFloat(entry.cost_per_liter).toFixed(2)}</td>
                  <td>
                    <span className="status-badge available">
                      <span />रु {parseFloat(entry.total_cost).toLocaleString()}
                    </span>
                  </td>
                  <td>
                    {entry.odometer_km
                      ? `${entry.odometer_km} km`
                      : <span className="muted">—</span>}
                  </td>
                  <td>
                    {entry.notes && entry.notes.trim()
                      ? entry.notes
                      : <span className="muted">—</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

import { useState, useEffect, useCallback, useMemo } from 'react';
import { api } from '../api/auth';
import {
  AlertTriangle,
  CheckCircle2,
  Eye,
  Search,
  ShieldCheck,
  Truck,
  X,
} from 'lucide-react';
import { fetchIssueReports, updateIssueStatus, getIssueImageUrl, type IssueReport } from '../api/issues';

const STATUS_BADGES: Record<string, { className: string; label: string }> = {
  open: { className: 'issue-open', label: 'Open' },
  acknowledged: { className: 'issue-acknowledged', label: 'Acknowledged' },
  resolved: { className: 'issue-resolved', label: 'Resolved' },
};

export default function IssuesTab() {
  const [reports, setReports] = useState<IssueReport[]>([]);
  const [loading, setLoading] = useState(true);
  const [dataError, setDataError] = useState<string | null>(null);
  const [vehicles, setVehicles] = useState<{ id: number; name: string }[]>([]);
  const [query, setQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [updatingId, setUpdatingId] = useState<number | null>(null);
  const [previewImage, setPreviewImage] = useState<string | null>(null);

  const fetchIssues = useCallback(async () => {
    try {
      const [reportsRes, vehiclesRes] = await Promise.all([
        fetchIssueReports(),
        api.get('/vehicles/'),
      ]);
      setReports(reportsRes);
      setVehicles(vehiclesRes.data);
      setDataError(null);
    } catch (error) {
      console.error('Failed to fetch issue reports', error);
      setDataError('Issue reports could not be refreshed.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchIssues();
  }, [fetchIssues]);

  const handleStatusChange = async (id: number, newStatus: IssueReport['status']) => {
    setUpdatingId(id);
    try {
      const updated = await updateIssueStatus(id, newStatus);
      setReports(prev => prev.map(r => r.id === id ? updated : r));
    } catch (error) {
      console.error('Failed to update issue status', error);
      setDataError('Could not update issue status.');
    } finally {
      setUpdatingId(null);
    }
  };

  const filteredReports = useMemo(() => {
    return reports.filter(r => {
      const matchesQuery = !query.trim() ||
        r.description.toLowerCase().includes(query.toLowerCase()) ||
        r.driver_name.toLowerCase().includes(query.toLowerCase()) ||
        r.vehicle_name.toLowerCase().includes(query.toLowerCase());
      const matchesStatus = statusFilter === 'all' || r.status === statusFilter;
      return matchesQuery && matchesStatus;
    });
  }, [reports, query, statusFilter]);

  const openCount = reports.filter(r => r.status === 'open').length;
  const acknowledgedCount = reports.filter(r => r.status === 'acknowledged').length;

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
    <section className="tab-content" aria-labelledby="issues-heading">
      <div className="page-heading">
        <div>
          <h2 id="issues-heading">Reported issues</h2>
          <p>Driver-flagged vehicle issues awaiting review.</p>
        </div>
      </div>

      {/* Summary metrics */}
      <div className="metrics-grid" style={{ marginBottom: 20 }}>
        <article className="metric-card">
          <div className="metric-heading"><span>Total reports</span><AlertTriangle size={17} /></div>
          <strong>{reports.length}</strong>
          <p>All issue reports</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Open</span><ShieldCheck size={17} /></div>
          <strong style={{ color: openCount > 0 ? 'var(--warning)' : undefined }}>{openCount}</strong>
          <p style={{ color: openCount > 0 ? 'var(--warning)' : undefined }}>Needs attention</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Acknowledged</span><Eye size={17} /></div>
          <strong>{acknowledgedCount}</strong>
          <p>In progress</p>
        </article>
        <article className="metric-card">
          <div className="metric-heading"><span>Resolved</span><CheckCircle2 size={17} /></div>
          <strong>{reports.filter(r => r.status === 'resolved').length}</strong>
          <p>Closed</p>
        </article>
      </div>

      {dataError && (
        <div className="global-alert" role="alert" style={{ marginBottom: 16, borderRadius: 7 }}>
          <AlertTriangle size={16} /><span>{dataError}</span>
          <button onClick={() => setDataError(null)} aria-label="Dismiss"><X size={15} /></button>
        </div>
      )}

      {/* Toolbar */}
      <div className="section-toolbar">
        <div>
          <h2>All reports</h2>
          <span>{reports.length} entries</span>
        </div>
        <div className="toolbar-controls">
          <div className="search-field">
            <Search size={15} />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Search issues"
              aria-label="Search issue reports"
            />
          </div>
          <select
            className="input-field"
            style={{ width: 150, minHeight: 36, fontSize: '.78rem' }}
            value={statusFilter}
            onChange={e => setStatusFilter(e.target.value)}
            aria-label="Filter by status"
          >
            <option value="all">All statuses</option>
            <option value="open">Open</option>
            <option value="acknowledged">Acknowledged</option>
            <option value="resolved">Resolved</option>
          </select>
        </div>
      </div>

      {filteredReports.length === 0 ? (
        <div className="empty-state">
          <div className="empty-icon"><AlertTriangle size={20} /></div>
          <h3>No issue reports</h3>
          <p>Driver-submitted issues will appear here once filed.</p>
        </div>
      ) : (
        <div className="data-table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Vehicle</th>
                <th>Driver</th>
                <th>Issue</th>
                <th>Photo</th>
                <th>Status</th>
                <th>Reported</th>
                <th><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              {filteredReports.map(report => {
                const preview = getIssueImageUrl(report.image);
                const isOpen = report.status === 'open';
                const isAcknowledged = report.status === 'acknowledged';
                return (
                  <tr key={report.id} className={!isOpen ? 'issue-resolved-row' : ''}>
                    <td>
                      <div className="primary-cell">
                        <div className="entity-icon"><Truck size={17} /></div>
                        <div><strong>{report.vehicle_name}</strong></div>
                      </div>
                    </td>
                    <td><span>{report.driver_name}</span></td>
                    <td>
                      <div style={{ maxWidth: 320 }}>
                        {report.description}
                      </div>
                    </td>
                    <td>
                      {preview ? (
                        <button
                          className="issue-photo-thumb"
                          onClick={() => setPreviewImage(preview)}
                          title="View full image"
                          aria-label={`View photo for issue ${report.id}`}
                        >
                          <img src={preview} alt="" loading="lazy" />
                        </button>
                      ) : (
                        <span className="muted">No photo</span>
                      )}
                    </td>
                    <td>
                      <span className={`status-badge ${STATUS_BADGES[report.status]?.className || 'neutral'}`}>
                        <span />
                        {STATUS_BADGES[report.status]?.label || report.status}
                      </span>
                    </td>
                    <td>
                      <span className="muted">
                        {new Date(report.created_at).toLocaleString(undefined, {
                          month: 'short',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit',
                        })}
                      </span>
                    </td>
                    <td>
                      <div className="row-actions">
                        {isOpen && (
                          <button
                            className="button button-primary"
                            style={{ minHeight: 30, padding: '4px 10px', fontSize: '.7rem' }}
                            onClick={() => handleStatusChange(report.id, 'acknowledged')}
                            disabled={updatingId === report.id}
                          >
                            {updatingId === report.id ? '...' : <><ShieldCheck size={13} /> Acknowledge</>}
                          </button>
                        )}
                        {isOpen && (
                          <button
                            className="button button-secondary"
                            style={{ minHeight: 30, padding: '4px 10px', fontSize: '.7rem' }}
                            onClick={() => handleStatusChange(report.id, 'resolved')}
                            disabled={updatingId === report.id}
                          >
                            {updatingId === report.id ? '...' : <><CheckCircle2 size={13} /> Resolve</>}
                          </button>
                        )}
                        {isAcknowledged && (
                          <button
                            className="button button-primary"
                            style={{ minHeight: 30, padding: '4px 10px', fontSize: '.7rem' }}
                            onClick={() => handleStatusChange(report.id, 'resolved')}
                            disabled={updatingId === report.id}
                          >
                            {updatingId === report.id ? '...' : <><CheckCircle2 size={13} /> Resolve</>}
                          </button>
                        )}
                        {report.status === 'resolved' && (
                          <span className="muted" style={{ fontSize: '.7rem' }}>Closed</span>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Image preview modal */}
      {previewImage && (
        <div className="modal-overlay" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setPreviewImage(null); }}>
          <div className="modal-content modal-compact" role="dialog" aria-modal="true" aria-labelledby="issue-preview-title">
            <div className="modal-header">
              <div>
                <span>Issue photo</span>
                <h2 id="issue-preview-title">Full size image</h2>
              </div>
              <button className="icon-button" onClick={() => setPreviewImage(null)} aria-label="Close preview"><X size={17} /></button>
            </div>
            <div className="modal-body" style={{ display: 'flex', justifyContent: 'center', background: 'var(--bg-tertiary)' }}>
              <img src={previewImage} alt="Issue photo" style={{ maxWidth: '100%', maxHeight: '70vh', borderRadius: 8, objectFit: 'contain' }} />
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

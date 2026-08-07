import { useState, useEffect } from 'react';
import {
  PieChart,
  Pie,
  Cell,
  BarChart,
  Bar,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { fetchAnalytics, type AnalyticsData } from '../api/vehicles';
import { CountUp } from '../hooks/useCountUp';
import {
  Truck, Activity, Users, MapPin, AlertTriangle, Clock, Fuel, CheckCircle2,
  Download, RefreshCw, Gauge, TrendingUp, ShieldCheck,
} from 'lucide-react';
import { toast } from './toast';

interface KpiCardProps {
  title: string;
  value: number;
  subtitle?: string;
  icon: React.ReactNode;
  accent?: string;
  suffix?: string;
  decimals?: number;
}

function KpiCard({ title, value, subtitle, icon, accent = 'var(--primary)', suffix = '', decimals = 0 }: KpiCardProps) {
  return (
    <article className="metric-card">
      <div className="metric-heading">
        <span>{title}</span>
        <div style={{ color: accent }}>{icon}</div>
      </div>
      <strong>
        <CountUp value={value} suffix={suffix} decimals={decimals} />
      </strong>
      <p>{subtitle}</p>
    </article>
  );
}

function CustomTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null;
  return (
    <div className="recharts-tooltip">
      <p className="recharts-tooltip-label">{label}</p>
      {payload.map((entry: any, index: number) => (
        <p key={index} style={{ color: entry.color }}>
          {entry.name}: {typeof entry.value === 'number' ? entry.value.toLocaleString() : entry.value}
        </p>
      ))}
    </div>
  );
}

function renderPieLabel(props: any) {
  const { cx, cy, midAngle, midRadius, percent } = props;
  if (percent < 0.06) return null;

  const RADIAN = Math.PI / 180;
  const radius = (midRadius || 100) * 0.62;
  const x = cx + radius * Math.cos(-midAngle * RADIAN);
  const y = cy + radius * Math.sin(-midAngle * RADIAN);

  return (
    <text
      x={x}
      y={y}
      textAnchor="middle"
      dominantBaseline="central"
      fill="var(--text-main)"
      fontSize={11}
      fontWeight={700}
    >
      {`${(percent * 100).toFixed(0)}%`}
    </text>
  );
}

function ChartSection({ title, subtitle, children, actions }: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  actions?: React.ReactNode;
}) {
  return (
    <div className="analytics-section">
      <div className="analytics-section-head">
        <div>
          <h3>{title}</h3>
          {subtitle && <p>{subtitle}</p>}
        </div>
        {actions}
      </div>
      <div className="charts-grid">{children}</div>
    </div>
  );
}

export default function AnalyticsDashboard() {
  const [analytics, setAnalytics] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [downloadingPdf, setDownloadingPdf] = useState(false);
  const [downloadingCsv, setDownloadingCsv] = useState(false);

  // Exports need the JWT in the Authorization header, so we fetch the file as a
  // blob and trigger a download rather than navigating to the URL.
  const downloadFile = async (url: string, filename: string) => {
    const response = await fetch(url, {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
      },
    });
    if (!response.ok) throw new Error(`Download failed (${response.status})`);
    const blob = await response.blob();
    const objectUrl = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = objectUrl;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(objectUrl);
    document.body.removeChild(a);
  };

  const downloadPdf = async () => {
    setDownloadingPdf(true);
    try {
      await downloadFile(
        '/api/expenses/report/pdf/',
        `sarthi_expenses_${new Date().toISOString().slice(0, 10)}.pdf`
      );
      toast.success('PDF downloaded successfully');
    } catch (err) {
      console.error('Failed to download PDF', err);
      toast.error('Failed to download PDF. Please try again.');
    } finally {
      setDownloadingPdf(false);
    }
  };

  const downloadCsv = async () => {
    setDownloadingCsv(true);
    try {
      await downloadFile('/api/dispatch/export/', 'dispatch_history.csv');
      toast.success('Dispatch CSV downloaded successfully');
    } catch (err) {
      console.error('Failed to download CSV', err);
      toast.error('Failed to download CSV. Please try again.');
    } finally {
      setDownloadingCsv(false);
    }
  };

  const refresh = () => {
    setLoading(true);
    setError(null);
    fetchAnalytics()
      .then(setAnalytics)
      .catch((err) => {
        console.error('Failed to fetch analytics', err);
        setError('Analytics data could not be loaded.');
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchAnalytics()
      .then(setAnalytics)
      .catch((err) => {
        console.error('Failed to fetch analytics', err);
        const message = 'Analytics data could not be loaded.';
        setError(message);
        toast.error(message);
      })
      .finally(() => setLoading(false));
  }, []);

  if (error) {
    return (
      <section className="tab-content" aria-labelledby="analytics-heading">
        <div className="page-heading">
          <div>
            <h2 id="analytics-heading">Analytics overview</h2>
            <p>Operational insights and trends.</p>
          </div>
        </div>
        <div className="inline-alert error" role="alert">
          <span>{error}</span>
          <button className="button button-secondary" style={{ marginLeft: 'auto' }} onClick={refresh}>Retry</button>
        </div>
      </section>
    );
  }

  if (loading || !analytics) {
    return (
      <section className="tab-content" aria-labelledby="analytics-heading">
        <div className="page-heading">
          <div>
            <h2 id="analytics-heading">Analytics overview</h2>
            <p>Operational insights and trends.</p>
          </div>
        </div>
        <div className="list-skeleton">{[1, 2, 3, 4].map(i => <div className="skeleton-row" key={i} />)}</div>
      </section>
    );
  }

  const { fleet_status, dispatch_volume, emergency_trends, vehicle_type_dist, top_drivers, issue_breakdown, fuel_trends, vehicle_efficiency, driver_performance, kpi } = analytics;

  const completionRate = kpi.total_dispatches ? Math.round((kpi.completed_dispatches / kpi.total_dispatches) * 100) : 0;

  return (
    <section className="tab-content" aria-labelledby="analytics-heading">
      <div className="page-heading">
        <div>
          <h2 id="analytics-heading">Analytics overview</h2>
          <p>Operational insights and trends for your fleet.</p>
        </div>
        <div className="heading-actions">
          <button className="button button-secondary" onClick={downloadPdf} disabled={downloadingPdf} title="Download expense summary PDF">
            <Download size={16} />
            {downloadingPdf ? 'Downloading…' : 'PDF report'}
          </button>
          <button className="button button-secondary" onClick={downloadCsv} disabled={downloadingCsv} title="Download dispatch history CSV">
            <Download size={16} />
            {downloadingCsv ? 'Downloading…' : 'CSV export'}
          </button>
          <button className="button button-secondary" onClick={refresh} title="Refresh analytics">
            <RefreshCw size={16} className={loading ? 'spin' : ''} />
            Refresh
          </button>
        </div>
      </div>

      {/* KPI band */}
      <div className="metrics-grid stagger" style={{ marginBottom: 26 }}>
        <KpiCard title="Fleet size" value={kpi.total_vehicles} subtitle={`${kpi.available} dispatch-ready`} icon={<Truck size={17} />} />
        <KpiCard title="Drivers" value={kpi.total_drivers} subtitle={`${kpi.active_drivers} on duty`} icon={<Users size={17} />} />
        <KpiCard title="Dispatches" value={kpi.total_dispatches} subtitle={`${kpi.completed_dispatches} completed`} icon={<Activity size={17} />} />
        <KpiCard title="Completion rate" value={completionRate} subtitle="Dispatch success" icon={<CheckCircle2 size={17} />} accent="var(--success)" suffix="%" />
        <KpiCard title="Avg response" value={kpi.avg_response_time_min ?? 0} subtitle="Dispatch to scene" icon={<Clock size={17} />} accent="var(--info)" suffix={kpi.avg_response_time_min != null ? ' min' : ''} />
        <KpiCard title="Pending SOS" value={kpi.pending_emergencies} subtitle="Active emergencies" icon={<MapPin size={17} />} accent="var(--danger)" />
        <KpiCard title="Open issues" value={kpi.open_issues} subtitle="Awaiting action" icon={<AlertTriangle size={17} />} accent="var(--warning)" />
        <KpiCard title="Fuel spend" value={kpi.total_fuel_cost} subtitle="Total cost (NPR)" icon={<Fuel size={17} />} accent="var(--warning)" />
      </div>

      {/* Fleet composition + activity */}
      <ChartSection title="Fleet & dispatch activity" subtitle="Live fleet composition and last 7 days of dispatches and emergencies.">
        <div className="chart-card" style={{ gridColumn: 'span 1' }}>
          <div className="chart-card-head">
            <h3>Fleet status</h3>
            <Gauge size={15} />
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie
                data={fleet_status}
                cx="50%"
                cy="50%"
                innerRadius={62}
                outerRadius={98}
                paddingAngle={3}
                dataKey="value"
                label={renderPieLabel}
                labelLine={false}
                stroke="none"
              >
                {fleet_status.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
              <Legend verticalAlign="bottom" height={36} iconType="circle" iconSize={8} />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card">
          <div className="chart-card-head">
            <h3>Dispatch volume</h3>
            <TrendingUp size={15} />
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={dispatch_volume} barCategoryGap="28%">
              <CartesianGrid vertical={false} strokeDasharray="3 3" />
              <XAxis dataKey="day" tick={{ fontSize: 11 }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 11 }} axisLine={false} tickLine={false} allowDecimals={false} />
              <Tooltip content={<CustomTooltip />} cursor={{ fill: 'color-mix(in srgb, var(--primary) 6%, transparent)' }} />
              <Bar dataKey="count" fill="var(--primary)" radius={[6, 6, 0, 0]} maxBarSize={34} name="Dispatches" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card">
          <div className="chart-card-head">
            <h3>Emergency trends</h3>
            <MapPin size={15} />
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={emergency_trends}>
              <CartesianGrid vertical={false} strokeDasharray="3 3" />
              <XAxis dataKey="day" tick={{ fontSize: 11 }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 11 }} axisLine={false} tickLine={false} allowDecimals={false} />
              <Tooltip content={<CustomTooltip />} />
              <Line type="monotone" dataKey="count" stroke="var(--danger)" strokeWidth={2.5} dot={{ r: 3, strokeWidth: 2, fill: 'var(--surface)' }} activeDot={{ r: 5 }} name="Emergencies" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </ChartSection>

      {/* Composition */}
      <ChartSection title="Fleet composition" subtitle="Vehicle mix, driver output and reported issue status.">
        <div className="chart-card">
          <div className="chart-card-head">
            <h3>Vehicle type mix</h3>
            <Truck size={15} />
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie
                data={vehicle_type_dist}
                cx="50%"
                cy="50%"
                outerRadius={96}
                dataKey="value"
                label={renderPieLabel}
                labelLine={false}
                stroke="none"
                paddingAngle={2}
              >
                {vehicle_type_dist.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
              <Legend verticalAlign="bottom" height={36} iconType="circle" iconSize={8} />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card">
          <div className="chart-card-head">
            <h3>Top drivers</h3>
            <ShieldCheck size={15} />
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={top_drivers} layout="vertical" barCategoryGap="30%">
              <CartesianGrid horizontal={false} strokeDasharray="3 3" />
              <XAxis type="number" tick={{ fontSize: 11 }} axisLine={false} tickLine={false} allowDecimals={false} />
              <YAxis dataKey="name" type="category" width={96} tick={{ fontSize: 11 }} axisLine={false} tickLine={false} />
              <Tooltip content={<CustomTooltip />} cursor={{ fill: 'color-mix(in srgb, var(--success) 6%, transparent)' }} />
              <Bar dataKey="completed" fill="var(--success)" radius={[0, 6, 6, 0]} maxBarSize={22} name="Completed" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card">
          <div className="chart-card-head">
            <h3>Issue status</h3>
            <AlertTriangle size={15} />
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie
                data={issue_breakdown}
                cx="50%"
                cy="50%"
                outerRadius={96}
                dataKey="value"
                label={renderPieLabel}
                labelLine={false}
                stroke="none"
                paddingAngle={2}
              >
                {issue_breakdown.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
              <Legend verticalAlign="bottom" height={36} iconType="circle" iconSize={8} />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </ChartSection>

      {/* Fuel analytics */}
      <ChartSection title="Fuel & consumption" subtitle="Daily fuel spend with volume and per-vehicle efficiency.">
        <div className="chart-card" style={{ gridColumn: '1 / -1' }}>
          <div className="chart-card-head">
            <h3>Fuel cost & consumption</h3>
            <Fuel size={15} />
          </div>
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={fuel_trends}>
              <CartesianGrid vertical={false} strokeDasharray="3 3" />
              <XAxis dataKey="day" tick={{ fontSize: 11 }} axisLine={false} tickLine={false} />
              <YAxis yAxisId="left" tick={{ fontSize: 11 }} axisLine={false} tickLine={false} />
              <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11 }} axisLine={false} tickLine={false} />
              <Tooltip content={<CustomTooltip />} />
              <Legend iconType="circle" iconSize={8} />
              <Line yAxisId="left" type="monotone" dataKey="cost" stroke="var(--warning)" strokeWidth={2.5} dot={{ r: 3, fill: 'var(--surface)', strokeWidth: 2 }} activeDot={{ r: 5 }} name="Cost (NPR)" />
              <Line yAxisId="right" type="monotone" dataKey="liters" stroke="var(--info)" strokeWidth={2.5} dot={{ r: 3, fill: 'var(--surface)', strokeWidth: 2 }} activeDot={{ r: 5 }} name="Liters" />
            </LineChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card" style={{ gridColumn: '1 / 2' }}>
          <div className="chart-card-head">
            <h3>Fuel efficiency (km/L)</h3>
            <Gauge size={15} />
          </div>
          {vehicle_efficiency.length > 0 ? (
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={vehicle_efficiency} barCategoryGap="28%">
                <CartesianGrid vertical={false} strokeDasharray="3 3" />
                <XAxis dataKey="vehicle_id" tick={{ fontSize: 11 }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 11 }} axisLine={false} tickLine={false} />
                <Tooltip content={<CustomTooltip />} cursor={{ fill: 'color-mix(in srgb, var(--success) 6%, transparent)' }} />
                <Bar dataKey="km_per_liter" fill="var(--success)" radius={[6, 6, 0, 0]} maxBarSize={34} name="km/L" />
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <div className="chart-empty">
              <Gauge size={26} />
              <p>No fuel efficiency data yet. Add fuel logs to see km/L per vehicle.</p>
            </div>
          )}
        </div>

        <div className="chart-card" style={{ gridColumn: '2 / -1' }}>
          <div className="chart-card-head">
            <h3>Driver performance</h3>
            <ShieldCheck size={15} />
          </div>
          {driver_performance.length > 0 ? (
            <div className="data-table-wrap table-inset">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Driver</th>
                    <th>Trips</th>
                    <th>Acceptance</th>
                    <th>Safety score</th>
                    <th>Harsh events</th>
                  </tr>
                </thead>
                <tbody>
                  {driver_performance.map((d) => (
                    <tr key={d.name}>
                      <td><strong style={{ color: 'var(--text-main)' }}>{d.name}</strong></td>
                      <td>{d.total_trips}</td>
                      <td>{d.acceptance_rate}%</td>
                      <td>
                        <span className={`score-pill ${d.score >= 80 ? 'score-good' : d.score >= 60 ? 'score-mid' : 'score-bad'}`}>
                          {d.score}
                        </span>
                      </td>
                      <td>
                        {d.harsh_events > 0 ? (
                          <span className="score-pill score-bad" title={`${d.events.harsh_accel} accel · ${d.events.harsh_brake} brake · ${d.events.harsh_turn} turn`}>
                            {d.harsh_events}
                          </span>
                        ) : (
                          <span style={{ color: 'var(--text-muted)', fontSize: '.72rem' }}>0</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="chart-empty">
              <ShieldCheck size={26} />
              <p>No driver trip data yet. Dispatched trips will appear here.</p>
            </div>
          )}
        </div>
      </ChartSection>
    </section>
  );
}

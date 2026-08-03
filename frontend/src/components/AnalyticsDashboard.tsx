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
import { Truck, Activity, Users, MapPin, AlertTriangle, Clock, Fuel, CheckCircle2 } from 'lucide-react';
import { toast } from './toast';

const COLORS = ['#10b981', '#f59e0b', '#ef4444', '#6366f1', '#8b5cf6'];

interface KpiCardProps {
  title: string;
  value: string | number;
  subtitle?: string;
  icon: React.ReactNode;
  trend?: 'up' | 'down' | 'neutral';
  accent?: string;
}

function KpiCard({ title, value, subtitle, icon, trend, accent = 'var(--accent)' }: KpiCardProps) {
  return (
    <article className="metric-card">
      <div className="metric-heading">
        <span>{title}</span>
        <div style={{ color: accent }}>{icon}</div>
      </div>
      <strong>{value}</strong>
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
  const { cx, cy, midAngle, midRadius, name, percent } = props;
  if (percent < 0.06) return null;

  const RADIAN = Math.PI / 180;
  const radius = (midRadius || 100) * 0.65;
  const x = cx + radius * Math.cos(-midAngle * RADIAN);
  const y = cy + radius * Math.sin(-midAngle * RADIAN);

  return (
    <text
      x={x}
      y={y}
      textAnchor="middle"
      dominantBaseline="central"
      fill="#ffffff"
      fontSize={11}
      fontWeight={700}
      style={{ textShadow: '0 1px 2px rgba(0,0,0,0.35)' }}
    >
      {`${(percent * 100).toFixed(0)}%`}
    </text>
  );
}

export default function AnalyticsDashboard() {
  const [analytics, setAnalytics] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
        <div className="list-skeleton">{[1, 2, 3].map(i => <div className="skeleton-row" key={i} />)}</div>
      </section>
    );
  }

  const { fleet_status, dispatch_volume, emergency_trends, vehicle_type_dist, top_drivers, issue_breakdown, fuel_trends, kpi } = analytics;

  return (
    <section className="tab-content" aria-labelledby="analytics-heading">
      <div className="page-heading">
        <div>
          <h2 id="analytics-heading">Analytics overview</h2>
          <p>Operational insights and trends for your Nepal fleet.</p>
        </div>
        <button className="button button-secondary" onClick={() => window.location.reload()} title="Refresh analytics">
          Refresh
        </button>
      </div>

      {/* KPI Cards */}
      <div className="metrics-grid" style={{ marginBottom: 24 }}>
        <KpiCard title="Fleet Size" value={kpi.total_vehicles} subtitle={`${kpi.available} available`} icon={<Truck size={17} />} />
        <KpiCard title="Drivers" value={kpi.total_drivers} subtitle={`${kpi.active_drivers} on duty`} icon={<Users size={17} />} />
        <KpiCard title="Dispatches" value={kpi.total_dispatches} subtitle={`${kpi.completed_dispatches} completed`} icon={<Activity size={17} />} />
        <KpiCard title="Avg Response" value={kpi.avg_response_time_min ? `${kpi.avg_response_time_min} min` : '—'} subtitle="Dispatch to scene" icon={<Clock size={17} />} />
        <KpiCard title="Pending SOS" value={kpi.pending_emergencies} subtitle="Active emergencies" icon={<MapPin size={17} />} accent="#ef4444" />
        <KpiCard title="Open Issues" value={kpi.open_issues} subtitle="Awaiting action" icon={<AlertTriangle size={17} />} accent="#f59e0b" />
        <KpiCard title="Fuel Spend" value={`रु ${kpi.total_fuel_cost.toLocaleString()}`} subtitle="Total cost" icon={<Fuel size={17} />} />
        <KpiCard title="Completion" value={kpi.total_dispatches ? `${Math.round((kpi.completed_dispatches / kpi.total_dispatches) * 100)}%` : '—'} subtitle="Dispatch success" icon={<CheckCircle2 size={17} />} accent="#10b981" />
      </div>

      {/* Charts Row 1 */}
      <div className="charts-grid" style={{ marginBottom: 24 }}>
        <div className="chart-card">
          <h3>Fleet Status</h3>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie
                data={fleet_status}
                cx="50%"
                cy="50%"
                innerRadius={60}
                outerRadius={100}
                paddingAngle={4}
                dataKey="value"
                label={renderPieLabel}
                labelLine={false}
              >
                {fleet_status.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
              <Legend verticalAlign="bottom" height={36} />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card">
          <h3>Dispatch Volume (Last 7 Days)</h3>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={dispatch_volume}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis dataKey="day" tick={{ fontSize: 12 }} />
              <YAxis tick={{ fontSize: 12 }} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="count" fill="#6366f1" radius={[4, 4, 0, 0]} name="Dispatches" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card">
          <h3>Emergency Trends</h3>
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={emergency_trends}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis dataKey="day" tick={{ fontSize: 12 }} />
              <YAxis tick={{ fontSize: 12 }} allowDecimals={false} />
              <Tooltip content={<CustomTooltip />} />
              <Line type="monotone" dataKey="count" stroke="#ef4444" strokeWidth={2} dot={{ fill: '#ef4444', r: 4 }} name="Emergencies" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Charts Row 2 */}
      <div className="charts-grid" style={{ marginBottom: 24 }}>
        <div className="chart-card">
          <h3>Vehicle Type Distribution</h3>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie
                data={vehicle_type_dist}
                cx="50%"
                cy="50%"
                outerRadius={100}
                dataKey="value"
                label={renderPieLabel}
                labelLine={false}
              >
                {vehicle_type_dist.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
              <Legend verticalAlign="bottom" height={36} />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card">
          <h3>Top Drivers (Completed Dispatches)</h3>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={top_drivers} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis type="number" tick={{ fontSize: 12 }} />
              <YAxis dataKey="name" type="category" width={100} tick={{ fontSize: 12 }} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="completed" fill="#10b981" radius={[0, 4, 4, 0]} name="Completed" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="chart-card">
          <h3>Issue Status Breakdown</h3>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie
                data={issue_breakdown}
                cx="50%"
                cy="50%"
                outerRadius={100}
                dataKey="value"
                label={renderPieLabel}
                labelLine={false}
              >
                {issue_breakdown.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
              <Legend verticalAlign="bottom" height={36} />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Charts Row 3 */}
      <div className="charts-grid">
        <div className="chart-card" style={{ gridColumn: '1 / -1' }}>
          <h3>Fuel Cost & Consumption Trends</h3>
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={fuel_trends}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis dataKey="day" tick={{ fontSize: 12 }} />
              <YAxis yAxisId="left" tick={{ fontSize: 12 }} />
              <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 12 }} />
              <Tooltip content={<CustomTooltip />} />
              <Legend />
              <Line yAxisId="left" type="monotone" dataKey="cost" stroke="#f59e0b" strokeWidth={2} dot={{ r: 4 }} name="Cost (NPR)" />
              <Line yAxisId="right" type="monotone" dataKey="liters" stroke="#3b82f6" strokeWidth={2} dot={{ r: 4 }} name="Liters" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>
    </section>
  );
}

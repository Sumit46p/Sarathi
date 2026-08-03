import React, { useState, useEffect } from 'react';
import { api } from '../api/auth';
import { AlertCircle, TrendingUp, Fuel, Wrench, DollarSign, Calendar, Truck, User, Search, Filter, X } from 'lucide-react';
import { toast } from './toast';

interface ExpenseSummary {
    total_fuel_cost: number;
    total_maintenance_cost: number;
    total_operational_cost: number;
    fuel_entries_count: number;
    maintenance_records_count: number;
    total_fuel_liters: number;
    average_fuel_cost_per_liter: number;
    by_vehicle: Array<{ vehicle: string; fuel_cost: number; count: number }>;
    by_driver: Array<{ driver: string; fuel_cost: number; count: number }>;
    date_range: { start: string | null; end: string | null };
}

interface DailyExpense {
    date: string;
    fuel_cost: number;
    fuel_count: number;
}

interface ExpenseReport {
    period_days: number;
    daily_breakdown: DailyExpense[];
    monthly_summary: Array<{ month: number; total: number }>;
}

export const ExpenseTab: React.FC = () => {
    const [summary, setSummary] = useState<ExpenseSummary | null>(null);
    const [report, setReport] = useState<ExpenseReport | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [startDate, setStartDate] = useState<string>('');
    const [endDate, setEndDate] = useState<string>('');
    const [period, setPeriod] = useState<number>(30);
    const [activeTab, setActiveTab] = useState<'overview' | 'report'>('overview');
    const [vehicleQuery, setVehicleQuery] = useState('');
    const [driverQuery, setDriverQuery] = useState('');

    // Fetch expense summary
    const fetchSummary = async (start?: string, end?: string) => {
        try {
            setLoading(true);
            let url = '/expenses/summary/';
            const params = new URLSearchParams();
            if (start) params.append('start_date', start);
            if (end) params.append('end_date', end);
            if (params.toString()) url += '?' + params.toString();

            const response = await api.get(url);
            setSummary({
                total_fuel_cost: Number(response.data.total_fuel_cost || 0),
                total_maintenance_cost: Number(response.data.total_maintenance_cost || 0),
                total_operational_cost: Number(response.data.total_operational_cost || 0),
                fuel_entries_count: Number(response.data.fuel_entries_count || 0),
                maintenance_records_count: Number(response.data.maintenance_records_count || 0),
                total_fuel_liters: Number(response.data.total_fuel_liters || 0),
                average_fuel_cost_per_liter: Number(response.data.average_fuel_cost_per_liter || 0),
                by_vehicle: (response.data.by_vehicle || []).map((v: any) => ({
                    vehicle: v.vehicle || 'Unknown',
                    fuel_cost: Number(v.fuel_cost || 0),
                    count: Number(v.count || 0),
                })),
                by_driver: (response.data.by_driver || []).map((d: any) => ({
                    driver: d.driver || 'Unknown',
                    fuel_cost: Number(d.fuel_cost || 0),
                    count: Number(d.count || 0),
                })),
                date_range: { start: start || null, end: end || null },
            });
            setError(null);
        } catch (err) {
            console.error('Failed to load expense summary:', err);
            setError('Failed to load expense summary. Please try again.');
            setSummary({
                total_fuel_cost: 0,
                total_maintenance_cost: 0,
                total_operational_cost: 0,
                fuel_entries_count: 0,
                maintenance_records_count: 0,
                total_fuel_liters: 0,
                average_fuel_cost_per_liter: 0,
                by_vehicle: [],
                by_driver: [],
                date_range: { start: start || null, end: end || null },
            });
        } finally {
            setLoading(false);
        }
    };

    // Fetch expense report
    const fetchReport = async (days: number) => {
        try {
            const response = await api.get(`/expenses/report/?period=${days}`);
            const dailyData = (response.data.daily_breakdown || []).map((item: any) => ({
                date: item.date || new Date().toISOString(),
                fuel_cost: Number(item.fuel_cost || 0),
                fuel_count: Number(item.fuel_count || 0),
            }));
            const monthlyData = (response.data.monthly_summary || []).map((item: any) => ({
                month: Number(item.month || 1),
                total: Number(item.total || 0),
            }));
            setReport({
                period_days: days,
                daily_breakdown: dailyData,
                monthly_summary: monthlyData,
            });
            setError(null);
        } catch (err) {
            console.error('Failed to load expense report:', err);
            setError('Failed to load expense report. Please try again.');
            setReport({
                period_days: days,
                daily_breakdown: [],
                monthly_summary: [],
            });
        }
    };

    useEffect(() => {
        fetchSummary();
        fetchReport(period);
    }, [period]);

    const handleFilterApply = () => {
        fetchSummary(startDate, endDate);
        fetchReport(period);
        toast.success('Filters applied');
    };

    const handleReset = () => {
        setStartDate('');
        setEndDate('');
        fetchSummary();
        fetchReport(period);
        toast.success('Filters reset');
    };

    const filteredVehicles = summary?.by_vehicle.filter(v =>
        v.vehicle.toLowerCase().includes(vehicleQuery.toLowerCase())
    ) || [];

    const filteredDrivers = summary?.by_driver.filter(d =>
        d.driver.toLowerCase().includes(driverQuery.toLowerCase())
    ) || [];

    if (loading) {
        return (
            <section className="tab-content">
                <div className="list-skeleton">{[1, 2, 3].map(i => <div className="skeleton-row" key={i} />)}</div>
            </section>
        );
    }

    return (
        <section className="tab-content" aria-labelledby="expense-heading">
            {/* Page Heading */}
            <div className="page-heading">
                <div>
                    <h2 id="expense-heading">Expense Tracking</h2>
                    <p>Monitor fuel and maintenance costs across your fleet.</p>
                </div>
            </div>

            {/* Tab Navigation */}
            <div className="section-toolbar" style={{ marginBottom: 20, borderBottom: '1px solid var(--border)', paddingBottom: 12 }}>
                <div style={{ display: 'flex', gap: 8 }}>
                    <button
                        className={`button ${activeTab === 'overview' ? 'button-primary' : 'button-secondary'}`}
                        onClick={() => setActiveTab('overview')}
                    >
                        <TrendingUp size={16} />
                        Overview
                    </button>
                    <button
                        className={`button ${activeTab === 'report' ? 'button-primary' : 'button-secondary'}`}
                        onClick={() => setActiveTab('report')}
                    >
                        <Calendar size={16} />
                        Report & Analytics
                    </button>
                </div>
            </div>

            {error && (
                <div className="global-alert" role="alert" style={{ marginBottom: 16, borderRadius: 7 }}>
                    <AlertCircle size={16} /><span>{error}</span>
                    <button onClick={() => setError(null)} aria-label="Dismiss"><X size={15} /></button>
                </div>
            )}

            {/* Overview Tab */}
            {activeTab === 'overview' && summary && (
                <>
                    {/* Summary Metrics */}
                    <div className="metrics-grid" style={{ marginBottom: 20 }}>
                        <article className="metric-card">
                            <div className="metric-heading"><span>Total Operational Cost</span><DollarSign size={17} /></div>
                            <strong>रु {summary.total_operational_cost.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                            <p>Combined fuel & maintenance</p>
                        </article>
                        <article className="metric-card">
                            <div className="metric-heading"><span>Total Fuel Cost</span><Fuel size={17} /></div>
                            <strong>रु {summary.total_fuel_cost.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                            <p>{summary.fuel_entries_count} transactions</p>
                        </article>
                        <article className="metric-card">
                            <div className="metric-heading"><span>Total Maintenance Cost</span><Wrench size={17} /></div>
                            <strong>रु {summary.total_maintenance_cost.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                            <p>{summary.maintenance_records_count} records</p>
                        </article>
                        <article className="metric-card">
                            <div className="metric-heading"><span>Avg Fuel Cost/Liter</span><TrendingUp size={17} /></div>
                            <strong>रु {summary.average_fuel_cost_per_liter.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                            <p>{summary.total_fuel_liters.toLocaleString()} L total</p>
                        </article>
                    </div>

                    {/* Date Filter */}
                    <div className="section-toolbar">
                        <div>
                            <h2>Filter by Date Range</h2>
                            <span>Customize expense view</span>
                        </div>
                        <div className="toolbar-controls" style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                            <input
                                type="date"
                                className="input-field"
                                value={startDate}
                                onChange={(e) => setStartDate(e.target.value)}
                                style={{ width: 140 }}
                            />
                            <span style={{ color: 'var(--text-secondary)' }}>to</span>
                            <input
                                type="date"
                                className="input-field"
                                value={endDate}
                                onChange={(e) => setEndDate(e.target.value)}
                                style={{ width: 140 }}
                            />
                            <button className="button button-primary" onClick={handleFilterApply}>
                                <Filter size={16} />
                                Apply
                            </button>
                            <button className="button button-secondary" onClick={handleReset}>
                                Reset
                            </button>
                        </div>
                    </div>

                    {/* By Vehicle Breakdown */}
                    {summary.by_vehicle && summary.by_vehicle.length > 0 && (
                        <>
                            <div className="section-toolbar" style={{ marginTop: 24 }}>
                                <div>
                                    <h2>Expenses by Vehicle</h2>
                                    <span>{filteredVehicles.length} vehicles</span>
                                </div>
                                <div className="search-field">
                                    <Search size={15} />
                                    <input
                                        value={vehicleQuery}
                                        onChange={(e) => setVehicleQuery(e.target.value)}
                                        placeholder="Search vehicles"
                                        aria-label="Search vehicles"
                                    />
                                </div>
                            </div>
                            <div className="data-table-wrap">
                                <table className="data-table">
                                    <thead>
                                        <tr>
                                            <th>Vehicle</th>
                                            <th style={{ textAlign: 'right' }}>Fuel Cost</th>
                                            <th style={{ textAlign: 'center' }}>Transactions</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {filteredVehicles.map((row, idx) => (
                                            <tr key={idx}>
                                                <td>
                                                    <div className="primary-cell">
                                                        <div className="entity-icon"><Truck size={17} /></div>
                                                        <div><strong>{row.vehicle}</strong></div>
                                                    </div>
                                                </td>
                                                <td style={{ textAlign: 'right' }}>
                                                    <strong>रु {row.fuel_cost.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                                                </td>
                                                <td style={{ textAlign: 'center' }}>
                                                    <span className="status-badge neutral"><span />{row.count}</span>
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </>
                    )}

                    {/* By Driver Breakdown */}
                    {summary.by_driver && summary.by_driver.length > 0 && (
                        <>
                            <div className="section-toolbar" style={{ marginTop: 24 }}>
                                <div>
                                    <h2>Expenses by Driver</h2>
                                    <span>{filteredDrivers.length} drivers</span>
                                </div>
                                <div className="search-field">
                                    <Search size={15} />
                                    <input
                                        value={driverQuery}
                                        onChange={(e) => setDriverQuery(e.target.value)}
                                        placeholder="Search drivers"
                                        aria-label="Search drivers"
                                    />
                                </div>
                            </div>
                            <div className="data-table-wrap">
                                <table className="data-table">
                                    <thead>
                                        <tr>
                                            <th>Driver</th>
                                            <th style={{ textAlign: 'right' }}>Fuel Cost</th>
                                            <th style={{ textAlign: 'center' }}>Transactions</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {filteredDrivers.map((row, idx) => (
                                            <tr key={idx}>
                                                <td>
                                                    <div className="primary-cell">
                                                        <div className="entity-icon"><User size={17} /></div>
                                                        <div><strong>{row.driver}</strong></div>
                                                    </div>
                                                </td>
                                                <td style={{ textAlign: 'right' }}>
                                                    <strong>रु {row.fuel_cost.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                                                </td>
                                                <td style={{ textAlign: 'center' }}>
                                                    <span className="status-badge neutral"><span />{row.count}</span>
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </>
                    )}
                </>
            )}

            {/* Report Tab */}
            {activeTab === 'report' && report && (
                <>
                    {/* Period Selector */}
                    <div className="section-toolbar">
                        <div>
                            <h2>Expense Report</h2>
                            <span>Last {report.period_days} days</span>
                        </div>
                        <div className="toolbar-controls">
                            <div className="segmented-control" aria-label="Select period">
                                {[7, 30, 90].map((days) => (
                                    <button
                                        key={days}
                                        className={period === days ? 'active' : ''}
                                        onClick={() => setPeriod(days)}
                                    >
                                        Last {days} Days
                                    </button>
                                ))}
                            </div>
                        </div>
                    </div>

                    {/* Daily Breakdown */}
                    <div className="section-toolbar" style={{ marginTop: 24 }}>
                        <div>
                            <h2>Daily Breakdown</h2>
                            <span>{report.daily_breakdown.length} days</span>
                        </div>
                    </div>
                    {report.daily_breakdown && report.daily_breakdown.length > 0 ? (
                        <div className="data-table-wrap">
                            <table className="data-table">
                                <thead>
                                    <tr>
                                        <th>Date</th>
                                        <th style={{ textAlign: 'right' }}>Fuel Cost</th>
                                        <th style={{ textAlign: 'center' }}>Transactions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {report.daily_breakdown.map((row, idx) => {
                                        const cost = Number(row.fuel_cost || 0);
                                        const count = Number(row.fuel_count || 0);
                                        return (
                                            <tr key={idx}>
                                                <td>{new Date(row.date).toLocaleDateString()}</td>
                                                <td style={{ textAlign: 'right' }}>
                                                    <strong>रु {cost.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                                                </td>
                                                <td style={{ textAlign: 'center' }}>
                                                    <span className="status-badge neutral"><span />{count}</span>
                                                </td>
                                            </tr>
                                        );
                                    })}
                                </tbody>
                            </table>
                        </div>
                    ) : (
                        <div className="empty-state">
                            <div className="empty-icon"><Calendar size={20} /></div>
                            <h3>No daily data available</h3>
                            <p>No expense records found for the selected period.</p>
                        </div>
                    )}

                    {/* Monthly Summary */}
                    {report.monthly_summary && report.monthly_summary.length > 0 && (
                        <>
                            <div className="section-toolbar" style={{ marginTop: 24 }}>
                                <div>
                                    <h2>Monthly Summary</h2>
                                    <span>{report.monthly_summary.length} months</span>
                                </div>
                            </div>
                            <div className="data-table-wrap">
                                <table className="data-table">
                                    <thead>
                                        <tr>
                                            <th>Month</th>
                                            <th style={{ textAlign: 'right' }}>Total Cost</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {report.monthly_summary.map((row, idx) => {
                                            const monthName = new Date(2026, Number(row.month || 1) - 1).toLocaleString(
                                                'default',
                                                { month: 'long' }
                                            );
                                            const total = Number(row.total || 0);
                                            return (
                                                <tr key={idx}>
                                                    <td><strong>{monthName}</strong></td>
                                                    <td style={{ textAlign: 'right' }}>
                                                        <strong>रु {total.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                                                    </td>
                                                </tr>
                                            );
                                        })}
                                    </tbody>
                                </table>
                            </div>
                        </>
                    )}

                    {/* Key Insights */}
                    {report.daily_breakdown && report.daily_breakdown.length > 0 && (
                        <div className="metrics-grid" style={{ marginTop: 24 }}>
                            <article className="metric-card">
                                <div className="metric-heading"><span>Total Entries</span><TrendingUp size={17} /></div>
                                <strong>{report.daily_breakdown.reduce((sum, d) => sum + (Number(d.fuel_count) || 0), 0)}</strong>
                                <p>Fuel transactions</p>
                            </article>
                            <article className="metric-card">
                                <div className="metric-heading"><span>Avg Daily Cost</span><DollarSign size={17} /></div>
                                <strong>
                                    रु {(report.daily_breakdown.reduce((sum, d) => sum + (Number(d.fuel_cost) || 0), 0) / report.daily_breakdown.length)
                                        .toLocaleString('en-IN', { maximumFractionDigits: 2 })}
                                </strong>
                                <p>Per day average</p>
                            </article>
                            <article className="metric-card">
                                <div className="metric-heading"><span>Highest Daily Cost</span><TrendingUp size={17} /></div>
                                <strong>
                                    रु {Math.max(...report.daily_breakdown.map((d) => Number(d.fuel_cost) || 0))
                                        .toLocaleString('en-IN', { maximumFractionDigits: 2 })}
                                </strong>
                                <p>Peak spending day</p>
                            </article>
                        </div>
                    )}
                </>
            )}
        </section>
    );
};
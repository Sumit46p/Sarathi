import { useEffect, useState } from 'react';
import { RefreshCw, Search, Loader2 } from 'lucide-react';
import { api } from '../api/auth';

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
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');

  const fetchEntries = async () => {
    try {
      setLoading(true);
      setError(null);
      const res = await api.get('/api/fuel/');
      setEntries(res.data);
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to load fuel entries');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchEntries();
  }, []);

  const filteredEntries = entries.filter((e) => {
    const s = search.toLowerCase();
    return (
      e.vehicle_name.toLowerCase().includes(s) ||
      e.driver_name.toLowerCase().includes(s)
    );
  });

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Fuel Management</h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            Track fleet fuel consumption and costs.
          </p>
        </div>
        <div className="flex gap-2 w-full sm:w-auto">
          <div className="relative flex-1 sm:w-64">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search vehicle or driver..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-4 py-2 bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/50 dark:text-gray-200"
            />
          </div>
          <button
            onClick={fetchEntries}
            disabled={loading}
            className="p-2 bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors disabled:opacity-50"
            title="Refresh"
          >
            <RefreshCw className={`w-4 h-4 text-gray-600 dark:text-gray-400 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      <div className="bg-white dark:bg-gray-900 rounded-xl border border-gray-100 dark:border-gray-800 shadow-sm overflow-hidden">
        {loading ? (
          <div className="flex flex-col items-center justify-center p-12 text-gray-500">
            <Loader2 className="w-8 h-8 animate-spin text-blue-500 mb-4" />
            <p>Loading fuel records...</p>
          </div>
        ) : error ? (
          <div className="p-8 text-center">
            <p className="text-red-500 mb-4">{error}</p>
            <button
              onClick={fetchEntries}
              className="px-4 py-2 bg-red-50 dark:bg-red-500/10 text-red-600 dark:text-red-400 rounded-lg hover:bg-red-100 dark:hover:bg-red-500/20 font-medium text-sm transition-colors"
            >
              Try Again
            </button>
          </div>
        ) : filteredEntries.length === 0 ? (
          <div className="p-12 text-center text-gray-500 dark:text-gray-400">
            <p>No fuel records found.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm whitespace-nowrap">
              <thead className="bg-gray-50/50 dark:bg-gray-800/50 border-b border-gray-100 dark:border-gray-800 text-gray-500 dark:text-gray-400">
                <tr>
                  <th className="px-6 py-4 font-medium">Date & Time</th>
                  <th className="px-6 py-4 font-medium">Vehicle</th>
                  <th className="px-6 py-4 font-medium">Driver</th>
                  <th className="px-6 py-4 font-medium text-right">Liters</th>
                  <th className="px-6 py-4 font-medium text-right">Cost/L</th>
                  <th className="px-6 py-4 font-medium text-right">Total Cost</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
                {filteredEntries.map((entry) => (
                  <tr key={entry.id} className="hover:bg-gray-50/50 dark:hover:bg-gray-800/50 transition-colors">
                    <td className="px-6 py-4 text-gray-900 dark:text-gray-200">
                      {new Date(entry.fueled_at).toLocaleString(undefined, {
                        month: 'short',
                        day: 'numeric',
                        hour: 'numeric',
                        minute: '2-digit',
                      })}
                    </td>
                    <td className="px-6 py-4 font-medium text-gray-900 dark:text-gray-200">
                      {entry.vehicle_name}
                    </td>
                    <td className="px-6 py-4 text-gray-600 dark:text-gray-400">
                      {entry.driver_name}
                    </td>
                    <td className="px-6 py-4 text-right text-gray-900 dark:text-gray-200 font-medium">
                      {entry.liters} L
                    </td>
                    <td className="px-6 py-4 text-right text-gray-500 dark:text-gray-400">
                      रु {entry.cost_per_liter}
                    </td>
                    <td className="px-6 py-4 text-right">
                      <span className="inline-flex items-center px-2.5 py-1 bg-green-50 dark:bg-green-500/10 text-green-700 dark:text-green-400 rounded-full font-medium">
                        रु {entry.total_cost}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

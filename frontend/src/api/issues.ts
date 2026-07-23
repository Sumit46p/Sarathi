import { api } from './auth';

export interface IssueReport {
  id: number;
  driver: number;
  driver_name: string;
  vehicle_name: string;
  description: string;
  image: string | null;
  status: 'open' | 'acknowledged' | 'resolved';
  created_at: string;
}

const API_BASE = 'http://localhost:8000';

export function getIssueImageUrl(imagePath: string | null): string | null {
  if (!imagePath) return null;
  if (imagePath.startsWith('http') || imagePath.startsWith('/')) return imagePath;
  return `${API_BASE}/media/${imagePath}`;
}

export async function fetchIssueReports(): Promise<IssueReport[]> {
  const { data } = await api.get<IssueReport[]>('/issues/');
  return data;
}

export async function updateIssueStatus(id: number, status: IssueReport['status']): Promise<IssueReport> {
  const { data } = await api.patch<IssueReport>(`/issues/${id}/`, { status });
  return data;
}

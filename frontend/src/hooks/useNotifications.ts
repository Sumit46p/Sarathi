import { useState, useEffect, useCallback, useRef } from 'react';
import { api } from '../api/auth';
import type { NotificationItem } from '../components/NotificationBell';

const WS_BASE = 'ws://127.0.0.1:8000/ws';

export function useNotifications() {
  const [notifications, setNotifications] = useState<NotificationItem[]>([]);
  const wsRef = useRef<WebSocket | null>(null);

  const fetchInitial = useCallback(async () => {
    try {
      const { data } = await api.get('/drivers/me/notifications/');
      setNotifications(data);
    } catch (err) {
      console.error('Failed to fetch notifications via REST', err);
    }
  }, []);

  const connectWs = useCallback(() => {
    const token = localStorage.getItem('access_token');
    if (!token) return;

    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const wsUrl = `${WS_BASE}/notifications/?token=${token}`;
    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      console.log('WebSocket for notifications connected');
    };

    ws.onmessage = (event) => {
      try {
        const payload = JSON.parse(event.data);
        // The backend payload shape might differ slightly from NotificationItem, normalize it
        const newNotification: NotificationItem = {
          id: payload.id,
          type: payload.type || 'system',
          title: payload.title,
          message: payload.message,
          is_read: payload.read || false,
          created_at: payload.timestamp || new Date().toISOString(),
        };

        setNotifications((prev) => {
          // Check for dupes just in case
          if (prev.some(n => n.id === newNotification.id)) return prev;
          return [newNotification, ...prev];
        });
      } catch (err) {
        console.error('Failed to parse WS message', err);
      }
    };

    ws.onclose = (e) => {
      console.log('WebSocket for notifications closed', e.reason);
      // Reconnect after 3s if not a clean shutdown
      if (e.code !== 4001) {
        setTimeout(connectWs, 3000);
      }
    };

    wsRef.current = ws;
  }, []);

  useEffect(() => {
    fetchInitial();
    connectWs();

    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, [fetchInitial, connectWs]);

  const markAsRead = useCallback(async (ids: number[]) => {
    // Optimistic update
    setNotifications((prev) =>
      prev.map((n) => (ids.includes(n.id as number) ? { ...n, is_read: true } : n))
    );
    // Real implementation would also call a backend endpoint to mark read,
    // e.g. api.post('/notifications/mark-read/', { ids });
  }, []);

  const deleteNotification = useCallback(async (id: number) => {
    setNotifications((prev) => prev.filter((n) => n.id !== id));
    // e.g. api.delete(`/notifications/${id}/`)
  }, []);

  return { notifications, markAsRead, deleteNotification };
}

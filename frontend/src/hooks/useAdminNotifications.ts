import { useState, useEffect, useCallback, useRef } from 'react';
import type { NotificationItem } from '../components/NotificationBell';
import { toast } from '../components/toast';

const WS_BASE = 'ws://127.0.0.1:8000/ws';

export function useAdminNotifications() {
  const [notifications, setNotifications] = useState<NotificationItem[]>([]);
  const [isWsConnected, setIsWsConnected] = useState(false);
  const [issueTrigger, setIssueTrigger] = useState(0);
  const [emergencyTrigger, setEmergencyTrigger] = useState(0);
  const [maintenanceTrigger, setMaintenanceTrigger] = useState(0);
  const wsRef = useRef<WebSocket | null>(null);

  const connectWs = useCallback(() => {
    const token = localStorage.getItem('access_token');
    if (!token) return;

    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const wsUrl = `${WS_BASE}/notifications/?token=${token}`;
    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      console.log('Admin WebSocket connected');
      setIsWsConnected(true);
      // Fetch latest on reconnect to ensure no dropped messages
      setIssueTrigger(t => t + 1);
      setEmergencyTrigger(t => t + 1);
      setMaintenanceTrigger(t => t + 1);
    };

    ws.onmessage = (event) => {
      try {
        const payload = JSON.parse(event.data);
        
        const newNotification: NotificationItem = {
          id: payload.id,
          type: payload.type || 'system',
          title: payload.title,
          message: payload.message,
          is_read: payload.read || false,
          created_at: payload.timestamp || new Date().toISOString(),
        };

        setNotifications((prev) => {
          if (prev.some(n => n.id === newNotification.id)) return prev;
          return [newNotification, ...prev];
        });

        // Trigger refetch of underlying tables if needed
        if (payload.type === 'issue') {
          toast.error('⚠️ New Maintenance Issue Reported');
          setIssueTrigger(t => t + 1);
        } else if (payload.type === 'emergency') {
          toast.error('🚨 New Emergency SOS Received!', 6000);
          setEmergencyTrigger(t => t + 1);
        } else if (payload.type === 'admin' && payload.title?.includes('Maintenance')) {
          toast.info('New Maintenance Request');
          setMaintenanceTrigger(t => t + 1);
        }
      } catch (err) {
        console.error('Failed to parse WS message', err);
      }
    };

    ws.onclose = (e) => {
      console.log('Admin WebSocket closed', e.reason);
      setIsWsConnected(false);
      // Reconnect after 3s if not a clean shutdown
      if (e.code !== 4001) {
        setTimeout(connectWs, 3000);
      }
    };

    wsRef.current = ws;
  }, []);

  useEffect(() => {
    connectWs();
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, [connectWs]);

  const markAsRead = useCallback(async (ids: number[]) => {
    setNotifications((prev) =>
      prev.map((n) => (ids.includes(n.id as number) ? { ...n, is_read: true } : n))
    );
  }, []);

  const deleteNotification = useCallback(async (id: number) => {
    setNotifications((prev) => prev.filter((n) => n.id !== id));
  }, []);

  return { 
    notifications, markAsRead, deleteNotification, isWsConnected, setNotifications,
    issueTrigger, emergencyTrigger, maintenanceTrigger
  };
}

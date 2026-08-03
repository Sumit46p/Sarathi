import { useState, useRef, useEffect } from 'react';
import { Bell, Trash2, CheckCircle2, AlertTriangle, Info, ShieldCheck, CheckCheck } from 'lucide-react';
import './NotificationBell.css';

export interface NotificationItem {
  id: number;
  type: 'trip' | 'issue' | 'admin' | 'system' | 'emergency';
  title: string;
  message: string;
  is_read: boolean;
  created_at: string;
}

const TYPE_CONFIG: Record<string, { icon: typeof Bell; color: string; bg: string; border: string; label: string }> = {
  trip: { icon: CheckCircle2, color: '#047857', bg: '#ecfdf5', border: '#a7f3d0', label: 'Trip' },
  issue: { icon: AlertTriangle, color: '#b45309', bg: '#fffbeb', border: '#fde68a', label: 'Issue' },
  emergency: { icon: AlertTriangle, color: '#b91c1c', bg: '#fef2f2', border: '#fecaca', label: 'Emergency' },
  admin: { icon: ShieldCheck, color: '#1d4ed8', bg: '#eff6ff', border: '#bfdbfe', label: 'Admin' },
  system: { icon: Info, color: '#374151', bg: '#f9fafb', border: '#e5e7eb', label: 'System' },
};

function formatTime(iso: string) {
  const date = new Date(iso);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours}h ago`;
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export default function NotificationBell({
  notifications,
  onMarkRead,
  onDelete,
}: {
  notifications: NotificationItem[];
  onMarkRead: (ids: number[]) => void;
  onDelete: (id: number) => void;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [showAll, setShowAll] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  const unreadCount = notifications.filter(n => !n.is_read).length;
  const displayNotifications = showAll ? notifications : notifications.slice(0, 5);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleMarkAllRead = () => {
    const unreadIds = notifications.filter(n => !n.is_read).map(n => n.id);
    if (unreadIds.length > 0) onMarkRead(unreadIds);
  };

  const handleClearAll = () => {
    const ids = notifications.map(n => n.id);
    if (ids.length > 0 && window.confirm('Clear all notifications?')) {
      ids.forEach(id => onDelete(id));
    }
  };

  return (
    <div className="notification-wrapper" ref={menuRef}>
      <button
        className="notification-btn"
        onClick={() => {
          setIsOpen(!isOpen);
          setShowAll(false);
        }}
        aria-label="Notifications"
      >
        <Bell size={20} color="var(--text-secondary)" />
        {unreadCount > 0 && (
          <span className="notification-badge">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}
      </button>

      {isOpen && (
        <div className="notification-dropdown">
          <div className="notification-header">
            <div>
              <h3 className="notification-title">Notifications</h3>
              {unreadCount > 0 && (
                <p className="notification-subtitle">{unreadCount} unread</p>
              )}
            </div>
            <div className="notification-actions">
              {unreadCount > 0 && (
                <button
                  onClick={handleMarkAllRead}
                  className="notification-action-btn primary"
                >
                  <CheckCheck size={14} />
                  Mark all read
                </button>
              )}
              {notifications.length > 0 && (
                <button
                  onClick={handleClearAll}
                  className="notification-action-btn icon-only"
                  title="Clear all"
                >
                  <Trash2 size={16} />
                </button>
              )}
            </div>
          </div>

          <div className="notification-list">
            {notifications.length === 0 ? (
              <div className="notification-empty">
                <div className="notification-empty-icon">
                  <Bell size={24} />
                </div>
                <p style={{ fontSize: '14px', fontWeight: '500', color: 'var(--text-primary)', margin: 0 }}>No notifications yet</p>
                <p style={{ fontSize: '12px', color: 'var(--text-secondary)', margin: '4px 0 0 0' }}>We'll notify you when something arrives</p>
              </div>
            ) : (
              <div>
                {displayNotifications.map(notification => {
                  const config = TYPE_CONFIG[notification.type] || TYPE_CONFIG.system;
                  const Icon = config.icon;
                  const isUnread = !notification.is_read;

                  return (
                    <div
                      key={notification.id}
                      className={`notification-item ${isUnread ? 'unread' : ''}`}
                      onClick={() => {
                        if (isUnread) onMarkRead([notification.id]);
                      }}
                    >
                      <div className="notification-icon" style={{ backgroundColor: config.bg, border: `1px solid ${config.border}`, color: config.color }}>
                        <Icon size={18} />
                      </div>

                      <div className="notification-content">
                        <div className="notification-header-row">
                          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                            <h4 className="notification-item-title">{notification.title}</h4>
                            <span className="notification-tag" style={{ backgroundColor: config.bg, color: config.color, borderColor: config.border }}>
                              {config.label}
                            </span>
                          </div>
                          <span className="notification-time">{formatTime(notification.created_at)}</span>
                        </div>
                        <p className="notification-message">
                          {notification.message}
                        </p>
                      </div>

                      <div className="notification-item-actions">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onDelete(notification.id);
                          }}
                          className="notification-action-btn icon-only"
                          title="Delete notification"
                        >
                          <Trash2 size={14} />
                        </button>
                        {isUnread && (
                          <div className="notification-unread-dot" title="Unread" />
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {notifications.length > 5 && (
            <div className="notification-footer">
              <button
                onClick={() => setShowAll(!showAll)}
                className="notification-footer-btn"
              >
                {showAll ? 'Show less' : `View all ${notifications.length} notifications`}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

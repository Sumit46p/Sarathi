import { useState, useRef, useEffect } from 'react';
import { Bell, Trash2, CheckCircle2, AlertTriangle, Info, ShieldCheck, X, CheckCheck } from 'lucide-react';

export interface NotificationItem {
  id: number;
  type: 'trip' | 'issue' | 'admin' | 'system' | 'emergency';
  title: string;
  message: string;
  is_read: boolean;
  created_at: string;
}

const TYPE_CONFIG: Record<string, { icon: typeof Bell; color: string; bg: string; border: string; label: string }> = {
  trip: { icon: CheckCircle2, color: 'text-emerald-700', bg: 'bg-emerald-50', border: 'border-emerald-200', label: 'Trip' },
  issue: { icon: AlertTriangle, color: 'text-amber-700', bg: 'bg-amber-50', border: 'border-amber-200', label: 'Issue' },
  emergency: { icon: AlertTriangle, color: 'text-red-700', bg: 'bg-red-50', border: 'border-red-200', label: 'Emergency' },
  admin: { icon: ShieldCheck, color: 'text-blue-700', bg: 'bg-blue-50', border: 'border-blue-200', label: 'Admin' },
  system: { icon: Info, color: 'text-gray-700', bg: 'bg-gray-50', border: 'border-gray-200', label: 'System' },
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
    <div className="relative" ref={menuRef}>
      <button
        className="relative p-2 rounded-xl hover:bg-gray-100 dark:hover:bg-gray-800 transition-all duration-200 group"
        onClick={() => {
          setIsOpen(!isOpen);
          setShowAll(false);
        }}
        aria-label="Notifications"
      >
        <Bell className="w-5 h-5 text-gray-600 dark:text-gray-300 group-hover:text-gray-900 dark:group-hover:text-white transition-colors" />
        {unreadCount > 0 && (
          <span className="absolute -top-0.5 -right-0.5 flex h-5 min-w-[20px] items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white shadow-lg ring-2 ring-white dark:ring-gray-900 animate-pulse">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}
      </button>

      {isOpen && (
        <div className="absolute right-0 mt-3 w-[420px] max-w-[calc(100vw-32px)] bg-white dark:bg-gray-900 rounded-2xl shadow-2xl border border-gray-200 dark:border-gray-700 z-50 overflow-hidden transform origin-top-right transition-all animate-in fade-in zoom-in-95 duration-200">
          {/* Header */}
          <div className="px-5 py-4 border-b border-gray-100 dark:border-gray-800 flex justify-between items-center bg-gradient-to-r from-gray-50 to-white dark:from-gray-800/50 dark:to-gray-900">
            <div>
              <h3 className="font-semibold text-gray-900 dark:text-white text-base">Notifications</h3>
              {unreadCount > 0 && (
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{unreadCount} unread</p>
              )}
            </div>
            <div className="flex items-center gap-2">
              {unreadCount > 0 && (
                <button
                  onClick={handleMarkAllRead}
                  className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300 bg-blue-50 dark:bg-blue-900/20 hover:bg-blue-100 dark:hover:bg-blue-900/30 rounded-lg transition-colors"
                >
                  <CheckCheck size={13} />
                  Mark all read
                </button>
              )}
              {notifications.length > 0 && (
                <button
                  onClick={handleClearAll}
                  className="p-1.5 text-gray-400 hover:text-red-500 rounded-lg hover:bg-red-50 dark:hover:bg-red-500/10 transition-colors"
                  title="Clear all"
                >
                  <Trash2 size={14} />
                </button>
              )}
            </div>
          </div>

          {/* Notification list */}
          <div className="max-h-[480px] overflow-y-auto">
            {notifications.length === 0 ? (
              <div className="py-16 px-4 text-center">
                <div className="mx-auto w-16 h-16 rounded-full bg-gray-50 dark:bg-gray-800 flex items-center justify-center mb-4">
                  <Bell className="w-8 h-8 text-gray-300 dark:text-gray-600" />
                </div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-200">No notifications yet</p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">We&apos;ll notify you when something arrives</p>
              </div>
            ) : (
              <div className="divide-y divide-gray-100 dark:divide-gray-800">
                {displayNotifications.map(notification => {
                  const config = TYPE_CONFIG[notification.type] || TYPE_CONFIG.system;
                  const Icon = config.icon;
                  const isUnread = !notification.is_read;

                  return (
                    <div
                      key={notification.id}
                      className={`group relative flex gap-3 p-4 hover:bg-gray-50 dark:hover:bg-gray-800/60 transition-all duration-150 cursor-pointer ${
                        isUnread ? 'bg-blue-50/40 dark:bg-blue-900/10' : ''
                      }`}
                      onClick={() => {
                        if (isUnread) onMarkRead([notification.id]);
                      }}
                    >
                      {/* Type indicator */}
                      <div className={`flex-shrink-0 mt-0.5 w-9 h-9 rounded-xl ${config.bg} border ${config.border} flex items-center justify-center`}>
                        <Icon className={`w-4 h-4 ${config.color}`} />
                      </div>

                      {/* Content */}
                      <div className="flex-1 min-w-0 pr-8">
                        <div className="flex items-start justify-between gap-2 mb-1">
                          <div className="flex items-center gap-2 flex-wrap">
                            <span className={`text-sm ${isUnread ? 'font-semibold text-gray-900 dark:text-white' : 'font-medium text-gray-700 dark:text-gray-200'}`}>
                              {notification.title}
                            </span>
                            <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium ${config.bg} ${config.color} ${config.border} border`}>
                              {config.label}
                            </span>
                          </div>
                          <span className="text-[11px] text-gray-400 dark:text-gray-500 whitespace-nowrap mt-0.5">
                            {formatTime(notification.created_at)}
                          </span>
                        </div>
                        <p className={`text-xs leading-relaxed line-clamp-2 ${isUnread ? 'text-gray-700 dark:text-gray-200' : 'text-gray-500 dark:text-gray-400'}`}>
                          {notification.message}
                        </p>
                      </div>

                      {/* Actions */}
                      <div className="absolute right-2 top-3 flex flex-col items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onDelete(notification.id);
                          }}
                          className="p-1.5 text-gray-400 hover:text-red-500 rounded-md hover:bg-red-50 dark:hover:bg-red-500/10 transition-colors"
                          title="Delete notification"
                        >
                          <Trash2 size={14} />
                        </button>
                        {isUnread && (
                          <div className="w-2 h-2 bg-blue-500 rounded-full mt-0.5" title="Unread" />
                        )}
                      </div>

                      {/* Unread indicator */}
                      {isUnread && (
                        <div className="absolute left-0 top-4 bottom-4 w-[3px] bg-blue-500 rounded-r-full" />
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Footer */}
          {notifications.length > 5 && (
            <div className="px-5 py-3 border-t border-gray-100 dark:border-gray-800 bg-gray-50/50 dark:bg-gray-800/30">
              <button
                onClick={() => setShowAll(!showAll)}
                className="w-full text-center text-xs font-medium text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white transition-colors"
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

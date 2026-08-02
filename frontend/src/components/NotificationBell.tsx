import { useState, useEffect } from 'react';
import { Bell, Trash2, CheckCircle2, AlertTriangle, Info, ShieldCheck, CheckCheck, X } from 'lucide-react';

export interface NotificationItem {
  id: number;
  type: 'trip' | 'issue' | 'admin' | 'system' | 'emergency';
  title: string;
  message: string;
  is_read: boolean;
  created_at: string;
}

const TYPE_CONFIG: Record<string, { icon: typeof Bell; color: string; bg: string; border: string; label: string }> = {
  trip: {
    icon: CheckCircle2,
    color: 'text-emerald-600 dark:text-emerald-300',
    bg: 'bg-emerald-50 dark:bg-emerald-500/15',
    border: 'border-emerald-200 dark:border-emerald-500/30',
    label: 'Trip',
  },
  issue: {
    icon: AlertTriangle,
    color: 'text-amber-600 dark:text-amber-300',
    bg: 'bg-amber-50 dark:bg-amber-500/15',
    border: 'border-amber-200 dark:border-amber-500/30',
    label: 'Issue',
  },
  emergency: {
    icon: AlertTriangle,
    color: 'text-rose-600 dark:text-rose-300',
    bg: 'bg-rose-50 dark:bg-rose-500/15',
    border: 'border-rose-200 dark:border-rose-500/30',
    label: 'Emergency',
  },
  admin: {
    icon: ShieldCheck,
    color: 'text-blue-600 dark:text-blue-300',
    bg: 'bg-blue-50 dark:bg-blue-500/15',
    border: 'border-blue-200 dark:border-blue-500/30',
    label: 'Admin',
  },
  system: {
    icon: Info,
    color: 'text-indigo-600 dark:text-indigo-300',
    bg: 'bg-indigo-50 dark:bg-indigo-500/15',
    border: 'border-indigo-200 dark:border-indigo-500/30',
    label: 'System',
  },
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

  const unreadCount = notifications.filter((n) => !n.is_read).length;
  const displayNotifications = showAll ? notifications : notifications.slice(0, 10);

  // Lock background scroll while the panel is open, and allow Escape to close it.
  useEffect(() => {
    if (!isOpen) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsOpen(false);
    };
    window.addEventListener('keydown', onKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [isOpen]);

  const handleMarkAllRead = () => {
    const unreadIds = notifications.filter((n) => !n.is_read).map((n) => n.id);
    if (unreadIds.length > 0) onMarkRead(unreadIds);
  };

  const handleClearAll = () => {
    const ids = notifications.map((n) => n.id);
    if (ids.length > 0 && window.confirm('Clear all notifications?')) {
      ids.forEach((id) => onDelete(id));
      setIsOpen(false);
    }
  };

  return (
    <div className="relative">
      {/* Bell trigger */}
      <button
        className="relative flex h-10 w-10 items-center justify-center rounded-full border border-gray-200 bg-white text-gray-600 shadow-sm transition-colors hover:bg-gray-50 hover:text-gray-900 focus:outline-none dark:border-gray-700 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-white"
        onClick={() => {
          setIsOpen(true);
          setShowAll(false);
        }}
        aria-label={unreadCount > 0 ? `Notifications, ${unreadCount} unread` : 'Notifications'}
        aria-expanded={isOpen}
      >
        <Bell className="h-5 w-5" strokeWidth={1.75} />
        {unreadCount > 0 && (
          <span className="absolute -right-1 -top-1 flex h-[18px] min-w-[18px] items-center justify-center rounded-full border-2 border-white bg-rose-500 px-1 text-[10px] font-semibold leading-none text-white dark:border-gray-900">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}
      </button>

      {isOpen && (
        <div className="fixed inset-0 z-[100] flex items-start justify-center px-4 pb-4 pt-[8vh] sm:pt-[10vh]">
          {/* Backdrop */}
          <div
            className="absolute inset-0 bg-gray-900/60 backdrop-blur-md transition-opacity dark:bg-black/80"
            onClick={() => setIsOpen(false)}
            aria-hidden="true"
          />

          {/* Panel */}
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Notifications"
            className="relative flex max-h-[80vh] w-full max-w-xl flex-col overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-xl dark:border-gray-700 dark:bg-gray-900"
          >
            {/* Header */}
            <div className="flex items-center justify-between gap-4 border-b border-gray-100 px-6 py-4 dark:border-gray-800">
              <div className="min-w-0">
                <h3 className="text-base font-semibold text-gray-900 dark:text-white">Notifications</h3>
                {unreadCount > 0 ? (
                  <p className="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                    {unreadCount} unread
                  </p>
                ) : (
                  <p className="mt-0.5 text-sm text-gray-500 dark:text-gray-400">You&apos;re all caught up</p>
                )}
              </div>

              <div className="flex items-center gap-1">
                {unreadCount > 0 && (
                  <button
                    onClick={handleMarkAllRead}
                    className="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm font-medium text-blue-600 transition-colors hover:bg-blue-50 dark:text-blue-400 dark:hover:bg-blue-500/10"
                  >
                    <CheckCheck size={15} />
                    <span className="hidden sm:inline">Mark all read</span>
                  </button>
                )}
                {notifications.length > 0 && (
                  <button
                    onClick={handleClearAll}
                    className="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-100 hover:text-rose-600 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-rose-400"
                    title="Clear all"
                    aria-label="Clear all notifications"
                  >
                    <Trash2 size={16} />
                  </button>
                )}
                <button
                  onClick={() => setIsOpen(false)}
                  className="rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-white"
                  aria-label="Close"
                >
                  <X size={18} />
                </button>
              </div>
            </div>

            {/* List */}
            <div className="flex-1 overflow-y-auto">
              {notifications.length === 0 ? (
                <div className="flex flex-col items-center px-6 py-20 text-center">
                  <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-gray-100 dark:bg-gray-800">
                    <Bell className="h-6 w-6 text-gray-400 dark:text-gray-500" strokeWidth={1.75} />
                  </div>
                  <p className="text-sm font-medium text-gray-900 dark:text-white">No notifications yet</p>
                  <p className="mt-1 max-w-xs text-sm text-gray-500 dark:text-gray-400">
                    We&apos;ll let you know when something needs your attention.
                  </p>
                </div>
              ) : (
                <ul className="divide-y divide-gray-100 dark:divide-gray-800">
                  {displayNotifications.map((notification) => {
                    const config = TYPE_CONFIG[notification.type] || TYPE_CONFIG.system;
                    const Icon = config.icon;
                    const isUnread = !notification.is_read;

                    return (
                      <li
                        key={notification.id}
                        className={`group relative flex gap-3 px-6 py-4 transition-colors hover:bg-gray-50 dark:hover:bg-gray-800/60 ${isUnread ? 'bg-blue-50/60 dark:bg-blue-500/[0.06]' : ''
                          }`}
                      >
                        <button
                          className="absolute inset-0 h-full w-full cursor-pointer"
                          onClick={() => isUnread && onMarkRead([notification.id])}
                          aria-label={isUnread ? `Mark "${notification.title}" as read` : notification.title}
                        />

                        {/* Icon */}
                        <div
                          className={`relative z-[1] mt-0.5 flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-full border ${config.bg} ${config.border}`}
                        >
                          <Icon className={`h-4.5 w-4.5 ${config.color}`} strokeWidth={2} />
                        </div>

                        {/* Content */}
                        <div className="relative z-[1] min-w-0 flex-1 pr-8">
                          <p
                            className={`text-sm font-semibold ${isUnread ? 'text-gray-900 dark:text-white' : 'text-gray-700 dark:text-gray-300'}`}
                          >
                            {notification.title}
                          </p>
                          <p className="mt-0.5 text-xs text-gray-400 dark:text-gray-500">
                            {formatTime(notification.created_at)}
                          </p>
                          <p
                            className={`mt-2 text-sm leading-relaxed ${isUnread ? 'text-gray-700 dark:text-gray-200' : 'text-gray-500 dark:text-gray-400'}`}
                          >
                            {notification.message}
                          </p>
                        </div>

                        {isUnread && (
                          <span className="absolute right-6 top-4 z-[1] h-2 w-2 flex-shrink-0 rounded-full bg-blue-500" />
                        )}

                        {/* Delete action */}
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onDelete(notification.id);
                          }}
                          className="absolute right-4 top-1/2 z-[2] -translate-y-1/2 rounded-lg border border-gray-200 bg-white p-1.5 text-gray-400 opacity-0 shadow-sm transition-opacity hover:text-rose-600 group-hover:opacity-100 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-500 dark:hover:text-rose-400"
                          title="Delete notification"
                          aria-label="Delete notification"
                        >
                          <Trash2 size={14} />
                        </button>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>

            {/* Footer */}
            {notifications.length > 10 && (
              <div className="border-t border-gray-100 px-6 py-3 text-center dark:border-gray-800">
                <button
                  onClick={() => setShowAll(!showAll)}
                  className="text-sm font-medium text-blue-600 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300"
                >
                  {showAll ? 'Show less' : `View all ${notifications.length} notifications`}
                </button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
import { useState, useEffect, useRef } from 'react';
import { Bell, Trash2, CheckCheck, X } from 'lucide-react';

export interface NotificationItem {
  id: number;
  type: 'trip' | 'issue' | 'admin' | 'system' | 'emergency' | 'fuel';
  title: string;
  message: string;
  is_read: boolean;
  created_at: string;
}

const TYPE_CONFIG: Record<string, { color: string; bg: string; border: string; label: string }> = {
  trip: {
    color: 'text-emerald-600 dark:text-emerald-400',
    bg: 'bg-emerald-50 dark:bg-emerald-500/10',
    border: 'border-emerald-200 dark:border-emerald-500/30',
    label: 'Trip',
  },
  issue: {
    color: 'text-amber-600 dark:text-amber-400',
    bg: 'bg-amber-50 dark:bg-amber-500/10',
    border: 'border-amber-200 dark:border-amber-500/30',
    label: 'Issue',
  },
  emergency: {
    color: 'text-rose-600 dark:text-rose-400',
    bg: 'bg-rose-50 dark:bg-rose-500/10',
    border: 'border-rose-200 dark:border-rose-500/30',
    label: 'Emergency',
  },
  admin: {
    color: 'text-blue-600 dark:text-blue-400',
    bg: 'bg-blue-50 dark:bg-blue-500/10',
    border: 'border-blue-200 dark:border-blue-500/30',
    label: 'Admin',
  },
  system: {
    color: 'text-indigo-600 dark:text-indigo-400',
    bg: 'bg-indigo-50 dark:bg-indigo-500/10',
    border: 'border-indigo-200 dark:border-indigo-500/30',
    label: 'System',
  },
  fuel: {
    color: 'text-sky-600 dark:text-sky-400',
    bg: 'bg-sky-50 dark:bg-sky-500/10',
    border: 'border-sky-200 dark:border-sky-500/30',
    label: 'Fuel',
  },
};

function formatTime(iso: string): string {
  const date = new Date(iso);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours}h ago`;
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays === 1) return 'Yesterday';
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

interface NotificationBellProps {
  notifications: NotificationItem[];
  onMarkRead: (ids: number[]) => void;
  onDelete: (id: number) => void;
}

export default function NotificationBell({ notifications, onMarkRead, onDelete }: NotificationBellProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);

  const unreadCount = notifications.filter(n => !n.is_read).length;
  const visibleNotifications = expanded ? notifications : notifications.slice(0, 5);
  const hasMore = notifications.length > 5;

  // Close on Escape
  useEffect(() => {
    if (!isOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [isOpen]);

  // Lock body scroll
  useEffect(() => {
    if (!isOpen) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prev;
    };
  }, [isOpen]);

  const handleMarkAllRead = () => {
    const unreadIds = notifications.filter(n => !n.is_read).map(n => n.id);
    if (unreadIds.length > 0) onMarkRead(unreadIds);
  };

  const handleClearAll = () => {
    const ids = notifications.map(n => n.id);
    if (ids.length > 0 && window.confirm('Clear all notifications?')) {
      ids.forEach(id => onDelete(id));
      setIsOpen(false);
    }
  };

  return (
    <div className="relative">
      {/* Bell trigger */}
      <button
        ref={triggerRef}
        className="relative flex h-10 w-10 items-center justify-center rounded-full border border-gray-200 bg-white text-gray-600 shadow-sm transition-all hover:border-gray-300 hover:text-gray-900 hover:shadow dark:border-gray-700 dark:bg-gray-800 dark:text-gray-200 dark:hover:border-gray-600 dark:hover:text-white"
        onClick={() => {
          setIsOpen(prev => !prev);
          setExpanded(false);
        }}
        aria-label={unreadCount > 0 ? `Notifications, ${unreadCount} unread` : 'Notifications'}
        aria-expanded={isOpen}
      >
        <Bell className="h-5 w-5" strokeWidth={1.75} />
        {unreadCount > 0 && (
          <span className="absolute -right-1 -top-1 flex h-[18px] min-w-[18px] items-center justify-center rounded-full border-2 border-white bg-rose-500 px-1 text-[10px] font-bold leading-none text-white dark:border-gray-900">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}
      </button>

      {isOpen && (
        <>
          {/* Backdrop */}
          <div
            className="fixed inset-0 z-[100] bg-gray-900/50 backdrop-blur-md transition-opacity dark:bg-black/70"
            onClick={() => setIsOpen(false)}
            aria-hidden="true"
          />

          {/* Panel */}
          <div
            className="fixed left-1/2 top-[8vh] z-[101] max-h-[85vh] w-[95vw] max-w-[420px] -translate-x-1/2 overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-2xl dark:border-gray-700 dark:bg-gray-900"
            role="dialog"
            aria-modal="true"
            aria-label="Notifications"
          >
            {/* Header */}
            <div className="flex items-center justify-between border-b border-gray-100 px-5 py-4 dark:border-gray-800">
              <div className="min-w-0">
                <h3 className="text-base font-semibold text-gray-900 dark:text-white">Notifications</h3>
                <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                  {unreadCount > 0 ? `${unreadCount} unread` : "You're all caught up"}
                </p>
              </div>
              <div className="flex items-center gap-1">
                {unreadCount > 0 && (
                  <button
                    onClick={handleMarkAllRead}
                    className="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium text-blue-600 transition-colors hover:bg-blue-50 dark:text-blue-400 dark:hover:bg-blue-500/10"
                  >
                    <CheckCheck size={14} />
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
                    <Trash2 size={15} />
                  </button>
                )}
                <button
                  onClick={() => setIsOpen(false)}
                  className="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-900 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-white"
                  aria-label="Close notifications"
                >
                  <X size={16} />
                </button>
              </div>
            </div>

            {/* List */}
            <div className="max-h-[60vh] overflow-y-auto">
              {notifications.length === 0 ? (
                <div className="flex flex-col items-center px-6 py-16 text-center">
                  <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-gray-100 dark:bg-gray-800">
                    <Bell className="h-5 w-5 text-gray-400 dark:text-gray-500" strokeWidth={1.75} />
                  </div>
                  <p className="text-sm font-medium text-gray-900 dark:text-white">No notifications yet</p>
                  <p className="mt-1 max-w-[260px] text-xs text-gray-500 dark:text-gray-400">
                    We&apos;ll notify you when something needs your attention.
                  </p>
                </div>
              ) : (
                <ul className="divide-y divide-gray-100 dark:divide-gray-800">
                  {visibleNotifications.map(notification => {
                    const config = TYPE_CONFIG[notification.type] || TYPE_CONFIG.system;
                    const isUnread = !notification.is_read;

                    return (
                      <li
                        key={notification.id}
                        className={`relative flex gap-3 px-5 py-4 transition-colors hover:bg-gray-50 dark:hover:bg-gray-800/60 group ${
                          isUnread ? 'bg-blue-50/60 dark:bg-blue-500/[0.08]' : ''
                        }`}
                      >
                        {/* Unread left accent */}
                        {isUnread && (
                          <div className="absolute left-0 top-3 bottom-3 w-[3px] rounded-r-full bg-blue-500 dark:bg-blue-400" />
                        )}

                        {/* Icon */}
                        <div
                          className={`relative z-[1] mt-0.5 flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-xl border ${config.bg} ${config.border}`}
                        >
                          <span className={`text-sm font-bold ${config.color}`}>
                            {config.label.charAt(0)}
                          </span>
                        </div>

                        {/* Content */}
                        <div className="relative z-[1] min-w-0 flex-1">
                          <div className="flex items-start justify-between gap-2">
                            <p
                              className={`text-sm leading-snug ${
                                isUnread ? 'font-semibold text-gray-900 dark:text-white' : 'font-medium text-gray-700 dark:text-gray-300'
                              }`}
                            >
                              {notification.title}
                            </p>
                            <time
                              className="mt-0.5 flex-shrink-0 text-[11px] text-gray-400 dark:text-gray-500"
                              dateTime={notification.created_at}
                            >
                              {formatTime(notification.created_at)}
                            </time>
                          </div>
                          <p
                            className={`mt-1.5 text-sm leading-relaxed ${
                              isUnread ? 'text-gray-700 dark:text-gray-200' : 'text-gray-500 dark:text-gray-400'
                            }`}
                          >
                            {notification.message}
                          </p>
                        </div>

                        {/* Delete action */}
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onDelete(notification.id);
                          }}
                          className="absolute right-3 top-3 z-[2] rounded-lg p-1.5 text-gray-300 opacity-0 transition-all hover:bg-rose-50 hover:text-rose-600 group-hover:opacity-100 dark:text-gray-600 dark:hover:bg-rose-500/10 dark:hover:text-rose-400"
                          title="Delete notification"
                          aria-label={`Delete notification: ${notification.title}`}
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
            {hasMore && (
              <div className="border-t border-gray-100 px-5 py-2.5 dark:border-gray-800">
                <button
                  onClick={() => setExpanded(prev => !prev)}
                  className="w-full text-center text-xs font-medium text-blue-600 transition-colors hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300"
                >
                  {expanded ? 'Show less' : `View all ${notifications.length} notifications`}
                </button>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

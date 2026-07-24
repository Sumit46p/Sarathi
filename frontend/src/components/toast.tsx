// Lightweight, dependency-free toast system.
//
// Usage:
//   import { toast } from '../components/toast';
//   toast.success('Vehicle added');
//   toast.error('Could not save');
//
// Mount <ToastViewport /> once near the app root (App.tsx). It subscribes to
// the toast store and renders the active toasts. Toasts auto-dismiss after a
// short delay and stack at the bottom-right. This is UI feedback only — it
// does not change any API or business logic.

import { CheckCircle2, AlertCircle, Info, X } from 'lucide-react';
import { useEffect, useState } from 'react';

export type ToastKind = 'success' | 'error' | 'info';

interface ToastEntry {
  id: number;
  kind: ToastKind;
  message: string;
}

type Listener = (toasts: ToastEntry[]) => void;

let nextId = 1;
let toasts: ToastEntry[] = [];
const listeners = new Set<Listener>();

function emit(): void {
  for (const listener of listeners) listener(toasts);
}

function addToast(kind: ToastKind, message: string, duration = 3200): void {
  const entry: ToastEntry = { id: nextId++, kind, message };
  toasts = [...toasts, entry];
  emit();
  if (duration > 0) {
    window.setTimeout(() => dismiss(entry.id), duration);
  }
}

export function dismiss(id: number): void {
  toasts = toasts.filter(t => t.id !== id);
  emit();
}

export const toast = {
  success: (message: string, duration?: number) => addToast('success', message, duration),
  error: (message: string, duration?: number) => addToast('error', message, duration),
  info: (message: string, duration?: number) => addToast('info', message, duration),
};

function useToasts(): ToastEntry[] {
  const [state, setState] = useState<ToastEntry[]>(toasts);
  useEffect(() => {
    listeners.add(setState);
    return () => {
      listeners.delete(setState);
    };
  }, []);
  return state;
}

const KIND_META: Record<ToastKind, { icon: typeof CheckCircle2; className: string }> = {
  success: { icon: CheckCircle2, className: 'toast-success' },
  error: { icon: AlertCircle, className: 'toast-error' },
  info: { icon: Info, className: 'toast-info' },
};

export function ToastViewport() {
  const active = useToasts();
  return (
    <div className="toast-viewport" role="region" aria-label="Notifications" aria-live="polite">
      {active.map(entry => {
        const meta = KIND_META[entry.kind];
        const Icon = meta.icon;
        return (
          <div key={entry.id} className={`toast ${meta.className}`} role="status">
            <Icon size={17} />
            <span>{entry.message}</span>
            <button className="toast-close" onClick={() => dismiss(entry.id)} aria-label="Dismiss notification">
              <X size={14} />
            </button>
          </div>
        );
      })}
    </div>
  );
}

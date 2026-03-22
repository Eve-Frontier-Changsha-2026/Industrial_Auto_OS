import { createContext, useCallback, useContext, useState } from "react";

export type ToastVariant = "ok" | "error" | "info";

export interface ToastItem {
  id: number;
  message: string;
  variant: ToastVariant;
}

interface ToastCtx {
  toasts: ToastItem[];
  addToast: (message: string, variant?: ToastVariant) => void;
  dismiss: (id: number) => void;
}

let nextId = 0;

export const ToastContext = createContext<ToastCtx>({
  toasts: [],
  addToast: () => {},
  dismiss: () => {},
});

export function useToastState() {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  const dismiss = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const addToast = useCallback(
    (message: string, variant: ToastVariant = "info") => {
      const id = nextId++;
      setToasts((prev) => [...prev, { id, message, variant }]);
      setTimeout(() => dismiss(id), 5000);
    },
    [dismiss],
  );

  return { toasts, addToast, dismiss };
}

export function useToast() {
  return useContext(ToastContext);
}

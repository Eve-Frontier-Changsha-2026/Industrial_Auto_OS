import { useState, useCallback } from "react";
import { DEFAULT_OPEN_PANES } from "../config/defaultLayout";

export function getDefaultPanes(): string[] {
  return [...DEFAULT_OPEN_PANES];
}

export function addPane(panes: Set<string>, id: string): Set<string> {
  return new Set([...panes, id]);
}

export function removePane(panes: Set<string>, id: string): Set<string> {
  const next = new Set(panes);
  next.delete(id);
  return next;
}

export function toggleMinimize(minimized: Set<string>, id: string): Set<string> {
  const next = new Set(minimized);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  return next;
}

export function usePaneManager() {
  const [openPanes, setOpenPanes] = useState<Set<string>>(() => new Set(DEFAULT_OPEN_PANES));
  const [minimized, setMinimized] = useState<Set<string>>(new Set());
  const [maximized, setMaximized] = useState<string | null>(null);

  const open = useCallback((id: string) => setOpenPanes((p) => addPane(p, id)), []);
  const close = useCallback((id: string) => {
    setOpenPanes((p) => removePane(p, id));
    setMinimized((m) => { const n = new Set(m); n.delete(id); return n; });
    if (maximized === id) setMaximized(null);
  }, [maximized]);
  const minimize = useCallback((id: string) => setMinimized((m) => toggleMinimize(m, id)), []);
  const maximize = useCallback((id: string) => setMaximized((prev) => (prev === id ? null : id)), []);

  return { openPanes, minimized, maximized, open, close, minimize, maximize };
}

import { useState, useCallback } from "react";
import type { Layout, LayoutItem } from "react-grid-layout";
import { DEFAULT_LAYOUT } from "../config/defaultLayout";

export const STORAGE_KEY = "industrial-auto-os-layout";

export function saveLayout(layout: LayoutItem[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(layout));
}

export function loadLayout(): LayoutItem[] | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as LayoutItem[];
  } catch {
    return null;
  }
}

export function useLayout() {
  const [layout, setLayout] = useState<LayoutItem[]>(() => loadLayout() ?? DEFAULT_LAYOUT);

  const onLayoutChange = useCallback((newLayout: Layout) => {
    setLayout([...newLayout]);
    saveLayout([...newLayout]);
  }, []);

  return { layout, onLayoutChange };
}

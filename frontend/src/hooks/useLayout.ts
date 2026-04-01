import { useState, useCallback } from "react";
import type { Layout, LayoutItem } from "react-grid-layout";
import { DEFAULT_LAYOUT } from "../config/defaultLayout";

export const STORAGE_KEY = "industrial-auto-os-layout";

export function saveLayout(layout: LayoutItem[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(layout));
}

function isLayoutArray(data: unknown): data is LayoutItem[] {
  if (!Array.isArray(data) || data.length === 0) return false;
  return data.every(
    (item) =>
      item !== null &&
      typeof item === "object" &&
      typeof (item as any).i === "string" &&
      typeof (item as any).x === "number" &&
      typeof (item as any).y === "number" &&
      typeof (item as any).w === "number" &&
      typeof (item as any).h === "number",
  );
}

export function loadLayout(): LayoutItem[] | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return isLayoutArray(parsed) ? parsed : null;
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

import type { LayoutItem } from "react-grid-layout";

export const DEFAULT_LAYOUT: LayoutItem[] = [
  { i: "system-overview",    x: 0,  y: 0,  w: 24, h: 4 },
  { i: "production-monitor", x: 0,  y: 4,  w: 10, h: 10 },
  { i: "work-order-board",   x: 10, y: 4,  w: 8,  h: 10 },
  { i: "activity-feed",      x: 18, y: 4,  w: 6,  h: 10 },
  { i: "trigger-engine",     x: 0,  y: 14, w: 10, h: 8 },
];

export const DEFAULT_OPEN_PANES = DEFAULT_LAYOUT.map((l) => l.i);

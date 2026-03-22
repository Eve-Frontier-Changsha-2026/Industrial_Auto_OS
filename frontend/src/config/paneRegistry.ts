import type { ComponentType } from "react";

export interface PaneDefinition {
  id: string;
  title: string;
  component: ComponentType;
  defaultSize: { w: number; h: number };
  minSize: { w: number; h: number };
  category: "dashboard" | "production" | "blueprint" | "orders" | "market" | "watcher" | "trigger";
}

// Placeholder until real components exist (Task 10-15).
const Placeholder = () => null;

export const PANE_DEFS: PaneDefinition[] = [
  { id: "system-overview",     title: "System Overview",      component: Placeholder, defaultSize: { w: 24, h: 4 },  minSize: { w: 8, h: 3 },  category: "dashboard" },
  { id: "activity-feed",       title: "Activity Feed",        component: Placeholder, defaultSize: { w: 8, h: 10 },  minSize: { w: 6, h: 4 },  category: "dashboard" },
  { id: "production-monitor",  title: "Production Monitor",   component: Placeholder, defaultSize: { w: 10, h: 10 }, minSize: { w: 8, h: 6 },  category: "production" },
  { id: "recipe-browser",      title: "Recipe Browser",       component: Placeholder, defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "production" },
  { id: "material-inventory",  title: "Material Inventory",   component: Placeholder, defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "production" },
  { id: "blueprint-inventory", title: "Blueprint Inventory",  component: Placeholder, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 4 },  category: "blueprint" },
  { id: "blueprint-mint",      title: "Blueprint Mint",       component: Placeholder, defaultSize: { w: 6, h: 6 },   minSize: { w: 5, h: 4 },  category: "blueprint" },
  { id: "work-order-board",    title: "Work Order Board",     component: Placeholder, defaultSize: { w: 12, h: 10 }, minSize: { w: 8, h: 6 },  category: "orders" },
  { id: "work-order-detail",   title: "Work Order Detail",    component: Placeholder, defaultSize: { w: 8, h: 10 },  minSize: { w: 6, h: 6 },  category: "orders" },
  { id: "work-order-create",   title: "Work Order Create",    component: Placeholder, defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 6 },  category: "orders" },
  { id: "market-listings",     title: "Market Listings",      component: Placeholder, defaultSize: { w: 12, h: 10 }, minSize: { w: 8, h: 6 },  category: "market" },
  { id: "lease-manager",       title: "Lease Manager",        component: Placeholder, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 5 },  category: "market" },
  { id: "watcher-status",      title: "Watcher Status",       component: Placeholder, defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "watcher" },
  { id: "tx-log",              title: "TX Log",               component: Placeholder, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 4 },  category: "watcher" },
  { id: "trigger-engine",      title: "Trigger Engine",       component: Placeholder, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 5 },  category: "trigger" },
];

export const PANE_MAP = new Map(PANE_DEFS.map((d) => [d.id, d]));

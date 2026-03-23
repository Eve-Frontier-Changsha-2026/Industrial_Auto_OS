import type { ComponentType } from "react";
import { SystemOverview } from "../panes/SystemOverview";
import { ActivityFeed } from "../panes/ActivityFeed";
import { ProductionMonitor } from "../panes/ProductionMonitor";
import { RecipeBrowser } from "../panes/RecipeBrowser";
import { MaterialInventory } from "../panes/MaterialInventory";
import { BlueprintInventory } from "../panes/BlueprintInventory";
import { BlueprintMint } from "../panes/BlueprintMint";
import { WorkOrderBoard } from "../panes/WorkOrderBoard";
import { WorkOrderDetail } from "../panes/WorkOrderDetail";
import { WorkOrderCreate } from "../panes/WorkOrderCreate";
import { MarketListings } from "../panes/MarketListings";
import { LeaseManager } from "../panes/LeaseManager";
import { WatcherStatus } from "../panes/WatcherStatus";
import { TxLog } from "../panes/TxLog";
import { TriggerEngine } from "../panes/TriggerEngine";
import { SSUInventory } from "../panes/SSUInventory";
import { GateAccess } from "../panes/GateAccess";
import { ItemMapping } from "../panes/ItemMapping";
import { LinkAssembly } from "../panes/LinkAssembly";

export interface PaneDefinition {
  id: string;
  title: string;
  component: ComponentType;
  defaultSize: { w: number; h: number };
  minSize: { w: number; h: number };
  category: "dashboard" | "production" | "blueprint" | "orders" | "market" | "watcher" | "trigger" | "eve";
}

export const PANE_DEFS: PaneDefinition[] = [
  { id: "system-overview",     title: "System Overview",      component: SystemOverview,     defaultSize: { w: 24, h: 4 },  minSize: { w: 8, h: 3 },  category: "dashboard" },
  { id: "activity-feed",       title: "Activity Feed",        component: ActivityFeed,       defaultSize: { w: 8, h: 10 },  minSize: { w: 6, h: 4 },  category: "dashboard" },
  { id: "production-monitor",  title: "Production Monitor",   component: ProductionMonitor,  defaultSize: { w: 10, h: 10 }, minSize: { w: 8, h: 6 },  category: "production" },
  { id: "recipe-browser",      title: "Recipe Browser",       component: RecipeBrowser,      defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "production" },
  { id: "material-inventory",  title: "Material Inventory",   component: MaterialInventory,  defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "production" },
  { id: "blueprint-inventory", title: "Blueprint Inventory",  component: BlueprintInventory, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 4 },  category: "blueprint" },
  { id: "blueprint-mint",      title: "Blueprint Mint",       component: BlueprintMint,      defaultSize: { w: 6, h: 6 },   minSize: { w: 5, h: 4 },  category: "blueprint" },
  { id: "work-order-board",    title: "Work Order Board",     component: WorkOrderBoard,     defaultSize: { w: 12, h: 10 }, minSize: { w: 8, h: 6 },  category: "orders" },
  { id: "work-order-detail",   title: "Work Order Detail",    component: WorkOrderDetail,    defaultSize: { w: 8, h: 10 },  minSize: { w: 6, h: 6 },  category: "orders" },
  { id: "work-order-create",   title: "Work Order Create",    component: WorkOrderCreate,    defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 6 },  category: "orders" },
  { id: "market-listings",     title: "Market Listings",      component: MarketListings,     defaultSize: { w: 12, h: 10 }, minSize: { w: 8, h: 6 },  category: "market" },
  { id: "lease-manager",       title: "Lease Manager",        component: LeaseManager,       defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 5 },  category: "market" },
  { id: "watcher-status",      title: "Watcher Status",       component: WatcherStatus,      defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "watcher" },
  { id: "tx-log",              title: "TX Log",               component: TxLog,              defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 4 },  category: "watcher" },
  { id: "trigger-engine",      title: "Trigger Engine",       component: TriggerEngine,      defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 5 },  category: "trigger" },
  { id: "ssu-inventory",       title: "SSU Inventory",        component: SSUInventory,       defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 5 },  category: "eve" },
  { id: "gate-access",         title: "Gate Access",          component: GateAccess,         defaultSize: { w: 12, h: 10 }, minSize: { w: 8, h: 6 },  category: "eve" },
  { id: "item-mapping",        title: "Item Mapping",         component: ItemMapping,        defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 5 },  category: "eve" },
  { id: "link-assembly",       title: "Link Assembly",        component: LinkAssembly,       defaultSize: { w: 8, h: 6 },   minSize: { w: 6, h: 4 },  category: "eve" },
];

export const PANE_MAP = new Map(PANE_DEFS.map((d) => [d.id, d]));

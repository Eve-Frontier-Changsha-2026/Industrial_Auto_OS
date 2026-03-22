export const PACKAGE_IDS = {
  industrial_core: import.meta.env.VITE_PKG_INDUSTRIAL_CORE ?? "",
  work_order: import.meta.env.VITE_PKG_WORK_ORDER ?? "",
  marketplace: import.meta.env.VITE_PKG_MARKETPLACE ?? "",
} as const;

export const SHARED_OBJECTS = {
  work_order_board: import.meta.env.VITE_WORK_ORDER_BOARD ?? "",
  marketplace: import.meta.env.VITE_MARKETPLACE ?? "",
} as const;

export const WATCHER_URL = import.meta.env.VITE_WATCHER_URL ?? "http://localhost:3001";

export const CLOCK_ID = "0x6";

export const TYPE_STRINGS = {
  BlueprintOriginal: (pkg: string) => `${pkg}::blueprint::BlueprintOriginal`,
  BlueprintCopy: (pkg: string) => `${pkg}::blueprint::BlueprintCopy`,
  Recipe: (pkg: string) => `${pkg}::recipe::Recipe`,
  ProductionLine: (pkg: string) => `${pkg}::production_line::ProductionLine`,
  TriggerRule: (pkg: string) => `${pkg}::trigger_engine::TriggerRule`,
  WorkOrder: (pkg: string) => `${pkg}::work_order::WorkOrder`,
  BpoListing: (pkg: string) => `${pkg}::marketplace::BpoListing`,
  BpcListing: (pkg: string) => `${pkg}::marketplace::BpcListing`,
  LeaseAgreement: (pkg: string) => `${pkg}::lease::LeaseAgreement`,
} as const;

import type { SuiEvent } from "@mysten/sui/client";

// ─── Signal Types ───────────────────────────────

export interface WatcherSignal {
  type: "event" | "inventory" | "deadline" | "fleet";
  eventData?: SuiEvent;
  inventoryData?: InventorySnapshot;
  deadlineData?: DeadlineRecord;
  fleetData?: MockDamageReport;
}

export interface InventorySnapshot {
  productionLineId: string;
  items: Map<number, number>; // item_type_id -> quantity
  status: number; // 0=IDLE, 1=RUNNING
  currentJobEnd: number; // timestamp ms, 0 if idle
  fuelReserve: number;
}

export interface DeadlineRecord {
  id: number;
  objectId: string;
  objectType: "work_order" | "lease";
  deadlineType: "deliver" | "auto_complete" | "expire" | "lease_forfeit";
  deadlineAt: number; // timestamp ms
}

export interface MockDamageReport {
  recipeId: string;
  quantity: number;
  priority: number;
  description: string;
}

// ─── Config Types ───────────────────────────────

export interface WatcherConfig {
  network: "devnet" | "testnet" | "mainnet";
  package_ids: {
    industrial_core: string;
    work_order: string;
    marketplace: string;
  };
  signer: {
    type: "single";
    keypath: string;
  };
  watch: {
    poll_interval_ms: number;
    production_line_ids: string[];
    work_order_board_id: string;
    marketplace_id: string;
    item_type_ids: number[];  // u32 Bag keys matching on-chain input_buffer
  };
  gas: {
    pool_size: number;
    min_balance_warn: number;
    min_coin_balance: number;
    auto_replenish: boolean;
  };
  rules: Record<string, RuleConfig>;
}

export interface RuleConfig {
  enabled: boolean;
  [key: string]: unknown;
}

// ─── Gas Pool Types ─────────────────────────────

export interface GasCoinEntry {
  objectId: string;
  version: string;
  digest: string;
  balance: number;
}

// ─── TX Log Types ───────────────────────────────

export type TxStatus = "success" | "failed" | "retrying";

export interface TxLogEntry {
  id?: number;
  ruleName: string;
  txDigest: string | null;
  status: TxStatus;
  error: string | null;
  signalData: string | null;
  gasCoinId: string | null;
  gasUsed: number | null;
  createdAt: number;
}

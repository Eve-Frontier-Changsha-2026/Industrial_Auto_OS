export interface Recipe {
  id: string;
  name: string;
  inputs: MaterialRequirement[];
  output: MaterialOutput;
  baseDurationMs: number;
  energyCost: number;
  creator: string;
}

export interface MaterialRequirement {
  itemTypeId: number;
  quantity: number;
}

export interface MaterialOutput {
  itemTypeId: number;
  quantity: number;
}

export interface BlueprintOriginal {
  id: string;
  recipeId: string;
  copiesMinted: number;
  maxCopies: number;
  materialEfficiency: number;
  timeEfficiency: number;
}

export interface BlueprintCopy {
  id: string;
  recipeId: string;
  sourceBpoId: string;
  usesRemaining: number;
  materialEfficiency: number;
  timeEfficiency: number;
}

export interface ProductionLine {
  id: string;
  owner: string;
  name: string;
  status: number; // 0=IDLE, 1=RUNNING
  recipeId: string;
  fuelReserve: number;
  jobsCompleted: number;
  currentJobEnd: number;
  operators: string[];
}

export interface WorkOrder {
  id: string;
  issuer: string;
  description: string;
  recipeId: string;
  quantityRequired: number;
  quantityDelivered: number;
  escrowValue: number;
  deadline: number;
  status: number;
  acceptor: string | null;
  priority: number;
  sourceEvent: string | null;
  deliveredAt: number | null;
}

export interface BpoListing {
  id: string;
  seller: string;
  price: number;
  active: boolean;
  bpoId: string;
}

export interface BpcListing {
  id: string;
  seller: string;
  price: number;
  active: boolean;
  bpcId: string;
}

export interface LeaseAgreement {
  id: string;
  lessor: string;
  lessee: string;
  expiry: number;
  dailyRate: number;
  depositValue: number;
  active: boolean;
}

export interface TriggerRule {
  id: string;
  productionLineId: string;
  conditionType: number;
  threshold: number;
  targetItemTypeId: number;
  enabled: boolean;
  lastTriggered: number;
  cooldownMs: number;
  autoRepeat: boolean;
}

// Status enums
export const PRODUCTION_STATUS = { IDLE: 0, RUNNING: 1 } as const;

export const ORDER_STATUS = {
  OPEN: 0, ACCEPTED: 1, DELIVERING: 2,
  DELIVERED: 3, COMPLETED: 4, CANCELLED: 5,
} as const;

export const ORDER_STATUS_LABEL: Record<number, string> = {
  0: "Open", 1: "Accepted", 2: "Delivering",
  3: "Delivered", 4: "Completed", 5: "Cancelled",
};

export const ORDER_PRIORITY_LABEL: Record<number, string> = {
  0: "Low", 1: "Normal", 2: "High", 3: "Critical",
};

export const TRIGGER_CONDITION = {
  INVENTORY_BELOW: 0,
  INVENTORY_ABOVE: 1,
} as const;

// === EVE Integration Types ===
export interface ItemMapping {
  eveTypeId: string; // u64 as string
  materialId: string;
}

export interface FactoryOverride {
  factoryId: string;
  disabledTypes: string[]; // eve_type_ids
}

export interface AccessPassData {
  id: string;
  factoryId: string;
  holder: string;
  passType: number; // 0=blueprint, 1=lease, 2=work_order
  expiresAt: string | null; // epoch ms or null
}

export const PASS_TYPE = {
  BLUEPRINT: 0,
  LEASE: 1,
  WORK_ORDER: 2,
} as const;

export const PASS_TYPE_LABEL: Record<number, string> = {
  0: "Blueprint Holder",
  1: "Lessee",
  2: "Work Order",
};

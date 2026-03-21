import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { startProduction } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class AutoRestock implements RuleHandler {
  readonly name = "auto_restock";
  readonly description = "Start production when inventory drops below threshold";
  readonly scheduleType = "inventory" as const;
  enabled = true;

  constructor(private corePackageId: string) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    const inv = signal.inventoryData;
    if (!inv) return false;
    if (inv.status !== 0) return false;
    const lineIds: string[] = (config as any).production_line_ids ?? [];
    if (!lineIds.includes(inv.productionLineId)) return false;
    const threshold = Number((config as any).threshold ?? 0);
    for (const [, qty] of inv.items) {
      if (qty < threshold) return true;
    }
    return false;
  }

  async buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    const recipeId = (config as any).recipe_id ?? "";
    const blueprintId = (config as any).blueprint_id ?? "";
    startProduction(tx, this.corePackageId, signal.inventoryData!.productionLineId, recipeId, blueprintId);
    return tx;
  }
}

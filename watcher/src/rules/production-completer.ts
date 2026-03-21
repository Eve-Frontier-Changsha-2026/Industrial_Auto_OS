import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { completeProduction } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class ProductionCompleter implements RuleHandler {
  readonly name = "production_completer";
  readonly description = "Complete finished production jobs";
  readonly scheduleType = "inventory" as const;
  enabled = true;

  constructor(private corePackageId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig, now?: number): Promise<boolean> {
    const inv = signal.inventoryData;
    if (!inv) return false;
    if (inv.status !== 1) return false;
    if (inv.currentJobEnd === 0) return false;
    return inv.currentJobEnd <= (now ?? Date.now());
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    completeProduction(tx, this.corePackageId, signal.inventoryData!.productionLineId);
    return tx;
  }
}

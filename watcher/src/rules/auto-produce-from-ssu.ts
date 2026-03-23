import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { Transaction } from "@mysten/sui/transactions";

export class AutoProduceFromSSU implements RuleHandler {
  readonly name = "auto_produce_from_ssu";
  readonly description = "Start production when SSU inventory has required materials";
  readonly scheduleType = "inventory" as const;
  enabled = true;

  constructor(private evePkgId: string) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    const inv = signal.inventoryData;
    if (!inv) return false;
    if (inv.status !== 0) return false; // not idle
    const ssuId = (config as any).ssu_id;
    if (!ssuId) return false;
    // Placeholder: would check SSU inventory via on-chain query
    // For now, trigger only when production line is idle
    return true;
  }

  async buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction> {
    const tx = new Transaction();
    // Placeholder: produce_from_ssu requires world types
    // When available: tx.moveCall({ target: `${this.evePkgId}::eve_bridge::produce_from_ssu`, ... })
    console.log(`[${this.name}] Would produce from SSU for line ${signal.inventoryData?.productionLineId}`);
    return tx;
  }
}

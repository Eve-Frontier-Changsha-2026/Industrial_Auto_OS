import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { Transaction } from "@mysten/sui/transactions";

export class AutoCollectToSSU implements RuleHandler {
  readonly name = "auto_collect_to_ssu";
  readonly description = "Deposit finished goods to SSU after production completes";
  readonly eventType = "ProductionCompletedEvent";
  enabled = true;

  constructor(private evePkgId: string) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    if (signal.type !== "event" || !signal.eventData) return false;
    const eventType = signal.eventData.type;
    if (!eventType.includes("ProductionCompletedEvent")) return false;
    const ssuId = (config as any).ssu_id;
    return !!ssuId;
  }

  async buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction> {
    const tx = new Transaction();
    // Placeholder: collect_to_ssu requires world types
    const parsed = signal.eventData?.parsedJson as any;
    console.log(`[${this.name}] Would collect to SSU from line ${parsed?.production_line_id}`);
    return tx;
  }
}

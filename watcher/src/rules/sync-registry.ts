import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { Transaction } from "@mysten/sui/transactions";

export class SyncRegistry implements RuleHandler {
  readonly name = "sync_registry";
  readonly description = "Log registry mapping changes and check for stale overrides";
  readonly eventType = "GlobalMappingAddedEvent";
  enabled = true;

  constructor(private evePkgId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    if (signal.type !== "event" || !signal.eventData) return false;
    const eventType = signal.eventData.type;
    return eventType.includes("GlobalMappingAddedEvent") ||
           eventType.includes("GlobalMappingRemovedEvent");
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Transaction();
    const parsed = signal.eventData?.parsedJson as any;
    const eventType = signal.eventData?.type ?? "";

    if (eventType.includes("GlobalMappingAddedEvent")) {
      console.log(`[${this.name}] New mapping: EVE ${parsed?.eve_type_id} → ${parsed?.material_id}`);
    } else if (eventType.includes("GlobalMappingRemovedEvent")) {
      console.log(`[${this.name}] Removed mapping: EVE ${parsed?.eve_type_id} → ${parsed?.material_id}`);
      console.log(`[${this.name}] Check factory overrides for stale references to type ${parsed?.eve_type_id}`);
    }

    // No on-chain action — this is a notification/audit rule
    return tx;
  }
}

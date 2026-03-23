import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { Transaction } from "@mysten/sui/transactions";

export class AutoGrantAccess implements RuleHandler {
  readonly name = "auto_grant_access";
  readonly description = "Auto-claim AccessPass when blueprint minted, lease created, or work order accepted";
  readonly eventType = "AccessGrantedEvent";
  enabled = true;

  constructor(private evePkgId: string) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    if (signal.type !== "event" || !signal.eventData) return false;
    const eventType = signal.eventData.type;
    // Trigger on relevant events from industrial_core, marketplace, or work_order
    const triggers = [
      "BlueprintMintedEvent",
      "LeaseCreatedEvent",
      "WorkOrderAcceptedEvent",
    ];
    return triggers.some((t) => eventType.includes(t));
  }

  async buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction> {
    const tx = new Transaction();
    const accessRegistryId = (config as any).access_registry_id ?? "";
    const parsed = signal.eventData?.parsedJson as any;
    const eventType = signal.eventData?.type ?? "";

    if (eventType.includes("BlueprintMintedEvent")) {
      const bpoId = parsed?.bpo_id;
      const lineId = (config as any).production_line_id;
      if (bpoId && lineId) {
        tx.moveCall({
          target: `${this.evePkgId}::factory_access::claim_from_blueprint`,
          arguments: [
            tx.object(accessRegistryId),
            tx.object(bpoId),
            tx.object(lineId),
          ],
        });
      }
    } else if (eventType.includes("LeaseCreatedEvent")) {
      const leaseId = parsed?.lease_id;
      const lineId = (config as any).production_line_id;
      if (leaseId && lineId) {
        tx.moveCall({
          target: `${this.evePkgId}::factory_access::claim_from_lease`,
          arguments: [
            tx.object(accessRegistryId),
            tx.object(leaseId),
            tx.object(lineId),
          ],
        });
      }
    } else if (eventType.includes("WorkOrderAcceptedEvent")) {
      const woId = parsed?.work_order_id;
      const lineId = (config as any).production_line_id;
      if (woId && lineId) {
        tx.moveCall({
          target: `${this.evePkgId}::factory_access::claim_from_work_order`,
          arguments: [
            tx.object(accessRegistryId),
            tx.object(woId),
            tx.object(lineId),
          ],
        });
      }
    }

    return tx;
  }
}

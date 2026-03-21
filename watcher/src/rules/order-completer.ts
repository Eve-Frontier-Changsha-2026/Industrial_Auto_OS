import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { completeWorkOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class OrderCompleter implements RuleHandler {
  readonly name = "order_completer";
  readonly description = "Complete delivered work orders (issuer)";
  readonly eventType = "WorkOrderDelivered";
  enabled = true;

  constructor(private woPackageId: string, private boardId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return !!signal.eventData?.parsedJson;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const parsed = signal.eventData!.parsedJson as Record<string, any>;
    const tx = new Tx();
    completeWorkOrder(tx, this.woPackageId, parsed.order_id, this.boardId);
    return tx;
  }
}

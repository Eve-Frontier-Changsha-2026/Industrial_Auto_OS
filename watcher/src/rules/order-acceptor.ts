import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { acceptWorkOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class OrderAcceptor implements RuleHandler {
  readonly name = "order_acceptor";
  readonly description = "Accept matching work orders";
  readonly eventType = "WorkOrderCreated";
  enabled = true;

  constructor(private woPackageId: string) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    const parsed = signal.eventData?.parsedJson as Record<string, any>;
    if (!parsed) return false;
    const maxEscrow = Number((config as any).max_escrow ?? Infinity);
    if (Number(parsed.escrow_amount) > maxEscrow) return false;
    const allowed: string[] = (config as any).recipe_ids ?? [];
    if (allowed.length > 0 && !allowed.includes(parsed.recipe_id)) return false;
    return true;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const parsed = signal.eventData!.parsedJson as Record<string, any>;
    const tx = new Tx();
    acceptWorkOrder(tx, this.woPackageId, parsed.order_id);
    return tx;
  }
}

import type { SuiClient } from "@mysten/sui/client";
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { deliverWorkOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class DeliveryHandler implements RuleHandler {
  readonly name = "delivery_handler";
  readonly description = "Auto-deliver for accepted orders (acceptor)";
  readonly eventType = "WorkOrderAccepted";
  enabled = true;

  constructor(private woPackageId: string, private client: SuiClient) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    if (!(config as any).auto_deliver) return false;
    return !!signal.eventData?.parsedJson;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const parsed = signal.eventData!.parsedJson as Record<string, any>;
    const orderId = parsed.order_id;
    const orderObj = await this.client.getObject({ id: orderId, options: { showContent: true } });
    const fields = (orderObj.data?.content as any)?.fields;
    const quantityRequired = Number(fields?.quantity_required ?? 0);
    const itemTypeId = 0;
    const tx = new Tx();
    deliverWorkOrder(tx, this.woPackageId, orderId, itemTypeId, quantityRequired);
    return tx;
  }
}

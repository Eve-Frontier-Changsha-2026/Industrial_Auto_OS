import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { withdrawOutput } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class OutputWithdrawer implements RuleHandler {
  readonly name = "output_withdrawer";
  readonly description = "Withdraw completed production output";
  readonly eventType = "ProductionCompletedEvent";
  enabled = true;

  constructor(private corePackageId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    const parsed = signal.eventData?.parsedJson as Record<string, any>;
    return !!parsed?.output_quantity && Number(parsed.output_quantity) > 0;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const parsed = signal.eventData!.parsedJson as Record<string, any>;
    const tx = new Tx();
    withdrawOutput(tx, this.corePackageId, parsed.production_line_id, Number(parsed.output_item_type_id), Number(parsed.output_quantity));
    return tx;
  }
}

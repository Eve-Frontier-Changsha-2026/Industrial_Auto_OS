import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { autoCompleteWorkOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class AutoComplete implements RuleHandler {
  readonly name = "auto_complete";
  readonly description = "Auto-complete work orders after 72h (acceptor)";
  readonly scheduleType = "deadline" as const;
  enabled = true;

  constructor(private woPackageId: string, private boardId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return signal.deadlineData?.deadlineType === "auto_complete";
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    autoCompleteWorkOrder(tx, this.woPackageId, signal.deadlineData!.objectId, this.boardId);
    return tx;
  }
}

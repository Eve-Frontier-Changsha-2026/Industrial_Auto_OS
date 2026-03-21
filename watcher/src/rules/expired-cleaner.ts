import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { cancelExpiredOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class ExpiredCleaner implements RuleHandler {
  readonly name = "expired_cleaner";
  readonly description = "Cancel expired work orders (permissionless)";
  readonly scheduleType = "deadline" as const;
  enabled = true;

  constructor(private woPackageId: string, private boardId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return signal.deadlineData?.deadlineType === "expire";
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    cancelExpiredOrder(tx, this.woPackageId, signal.deadlineData!.objectId, this.boardId);
    return tx;
  }
}

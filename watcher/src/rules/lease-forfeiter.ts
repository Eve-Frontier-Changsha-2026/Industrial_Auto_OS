import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { forfeitLease } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class LeaseForfeiter implements RuleHandler {
  readonly name = "lease_forfeiter";
  readonly description = "Forfeit expired leases (lessor)";
  readonly scheduleType = "deadline" as const;
  enabled = true;

  constructor(private mktPackageId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return signal.deadlineData?.deadlineType === "lease_forfeit";
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    forfeitLease(tx, this.mktPackageId, signal.deadlineData!.objectId);
    return tx;
  }
}

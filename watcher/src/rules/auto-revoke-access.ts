import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { Transaction } from "@mysten/sui/transactions";

const CLOCK_ID = "0x6";

export class AutoRevokeAccess implements RuleHandler {
  readonly name = "auto_revoke_access";
  readonly description = "Revoke expired AccessPasses automatically";
  readonly scheduleType = "deadline" as const;
  enabled = true;

  constructor(private evePkgId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig, now?: number): Promise<boolean> {
    if (signal.type !== "deadline" || !signal.deadlineData) return false;
    if (signal.deadlineData.deadlineType !== "expire") return false;
    const currentTime = now ?? Date.now();
    return currentTime > signal.deadlineData.deadlineAt;
  }

  async buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction> {
    const tx = new Transaction();
    const accessRegistryId = (config as any).access_registry_id ?? "";
    const passId = signal.deadlineData?.objectId ?? "";
    tx.moveCall({
      target: `${this.evePkgId}::factory_access::revoke_expired`,
      arguments: [
        tx.object(accessRegistryId),
        tx.object(passId),
        tx.object(CLOCK_ID),
      ],
    });
    return tx;
  }
}

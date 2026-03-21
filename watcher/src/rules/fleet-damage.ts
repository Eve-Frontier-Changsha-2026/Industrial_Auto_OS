import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { createOrderFromDamageReport } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class FleetDamageHandler implements RuleHandler {
  readonly name = "fleet_damage";
  readonly description = "Create work order from fleet damage report";
  readonly scheduleType = "fleet" as const;
  enabled = true;

  constructor(private woPackageId: string, private boardId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return signal.type === "fleet" && !!signal.fleetData;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const report = signal.fleetData!;
    const tx = new Tx();
    const deadline = Date.now() + 24 * 60 * 60 * 1000;
    createOrderFromDamageReport(
      tx, this.woPackageId, this.boardId,
      report.description, report.recipeId, report.quantity,
      "", deadline, `fleet_damage_${Date.now()}`,
    );
    return tx;
  }
}

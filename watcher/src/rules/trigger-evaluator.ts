import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { executeTrigger } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

interface TriggerRuleInfo {
  ruleId: string;
  productionLineId: string;
  recipeId: string;
  blueprintId: string;
}

export class TriggerEvaluator implements RuleHandler {
  readonly name = "trigger_evaluator";
  readonly description = "Evaluate on-chain trigger rules and execute them";
  readonly scheduleType = "inventory" as const;
  enabled = true;

  constructor(private corePackageId: string, private triggerRules: TriggerRuleInfo[]) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    const inv = signal.inventoryData;
    if (!inv) return false;
    const lineIds: string[] = (config as any).production_line_ids ?? [];
    return lineIds.includes(inv.productionLineId);
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    const lineId = signal.inventoryData!.productionLineId;
    const matchingRules = this.triggerRules.filter((r) => r.productionLineId === lineId);
    for (const rule of matchingRules) {
      executeTrigger(tx, this.corePackageId, rule.ruleId, lineId, rule.recipeId, rule.blueprintId);
    }
    return tx;
  }
}

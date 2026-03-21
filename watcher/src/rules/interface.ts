import type { Transaction } from "@mysten/sui/transactions";
import type { WatcherSignal, RuleConfig } from "../types.js";

export interface RuleHandler {
  readonly name: string;
  readonly description: string;
  readonly eventType?: string;
  readonly scheduleType?: "inventory" | "deadline" | "fleet";
  enabled: boolean;

  evaluate(signal: WatcherSignal, config: RuleConfig, now?: number): Promise<boolean>;
  buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction>;
}

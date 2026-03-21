import type Database from "better-sqlite3";
import type { WatcherConfig, WatcherSignal } from "./types.js";
import type { RuleRegistry } from "./rules/registry.js";
import type { TxExecutor } from "./executor/tx-executor.js";

export class WatcherEngine {
  private txExecutor: TxExecutor | null = null;

  constructor(
    private config: WatcherConfig,
    private db: Database.Database,
    private registry: RuleRegistry,
  ) {}

  setTxExecutor(executor: TxExecutor): void {
    this.txExecutor = executor;
  }

  async dispatch(signal: WatcherSignal): Promise<void> {
    let handlers;

    if (signal.type === "event" && signal.eventData) {
      handlers = this.registry.getByEventType(signal.eventData.type);
    } else if (signal.type === "inventory") {
      handlers = this.registry.getByScheduleType("inventory");
    } else if (signal.type === "deadline") {
      handlers = this.registry.getByScheduleType("deadline");
    } else if (signal.type === "fleet") {
      handlers = this.registry.getByScheduleType("fleet");
    } else {
      return;
    }

    for (const handler of handlers) {
      const ruleConfig = this.config.rules[handler.name] ?? { enabled: true };
      try {
        const shouldAct = await handler.evaluate(signal, ruleConfig);
        if (!shouldAct) continue;

        const tx = await handler.buildTx(signal, ruleConfig);

        if (this.txExecutor) {
          const result = await this.txExecutor.execute(
            handler.name, tx, JSON.stringify(signal),
          );
          if (result.success) {
            console.log(`[${handler.name}] TX success: ${result.digest}`);
          } else {
            console.error(`[${handler.name}] TX failed: ${result.error}`);
          }
        }
      } catch (err) {
        console.error(`[${handler.name}] Error:`, err);
      }
    }
  }
}

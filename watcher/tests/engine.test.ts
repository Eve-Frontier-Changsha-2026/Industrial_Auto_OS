import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import { WatcherEngine } from "../src/engine.js";
import { RuleRegistry } from "../src/rules/registry.js";
import { createDb } from "../src/db/sqlite.js";
import { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "../src/rules/interface.js";
import type { WatcherConfig } from "../src/types.js";

function makeTestConfig(): WatcherConfig {
  return {
    network: "testnet",
    package_ids: { industrial_core: "0xCORE", work_order: "0xWO", marketplace: "0xMKT" },
    signer: { type: "single", keypath: "" },
    watch: {
      poll_interval_ms: 100, production_line_ids: ["0xLINE1"],
      work_order_board_id: "0xBOARD", marketplace_id: "0xMARKET", item_type_ids: [1],
    },
    gas: { pool_size: 5, min_balance_warn: 100000000, min_coin_balance: 5000000, auto_replenish: true },
    rules: { output_withdrawer: { enabled: true } },
  };
}

describe("WatcherEngine", () => {
  let db: Database.Database;
  beforeEach(() => { db = createDb(":memory:"); });
  afterEach(() => db.close());

  it("dispatches event signals to matching rule handlers", async () => {
    const evaluateSpy = vi.fn().mockResolvedValue(true);
    const buildTxSpy = vi.fn().mockResolvedValue(new Transaction());
    const registry = new RuleRegistry();
    registry.register({
      name: "test_rule", description: "test", eventType: "ProductionCompletedEvent",
      enabled: true, evaluate: evaluateSpy, buildTx: buildTxSpy,
    });
    const engine = new WatcherEngine(makeTestConfig(), db, registry);
    await engine.dispatch({
      type: "event",
      eventData: {
        id: { txDigest: "0x1", eventSeq: "0" },
        type: "0xCORE::production_line::ProductionCompletedEvent",
        parsedJson: {}, packageId: "0xCORE", transactionModule: "production_line",
        sender: "0x", bcs: "", timestampMs: "0",
      },
    });
    expect(evaluateSpy).toHaveBeenCalledOnce();
    expect(buildTxSpy).toHaveBeenCalledOnce();
  });

  it("skips rules that evaluate to false", async () => {
    const buildTxSpy = vi.fn();
    const registry = new RuleRegistry();
    registry.register({
      name: "skip_me", description: "test", eventType: "SomeEvent",
      enabled: true, evaluate: vi.fn().mockResolvedValue(false), buildTx: buildTxSpy,
    });
    const engine = new WatcherEngine(makeTestConfig(), db, registry);
    await engine.dispatch({
      type: "event",
      eventData: {
        id: { txDigest: "0x1", eventSeq: "0" },
        type: "0xCORE::m::SomeEvent", parsedJson: {},
        packageId: "0xCORE", transactionModule: "m", sender: "0x", bcs: "", timestampMs: "0",
      },
    });
    expect(buildTxSpy).not.toHaveBeenCalled();
  });
});

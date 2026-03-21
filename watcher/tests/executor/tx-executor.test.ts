import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import { TxExecutor } from "../../src/executor/tx-executor.js";
import { GasPool } from "../../src/executor/gas-pool.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";
import { createDb } from "../../src/db/sqlite.js";
import type { SignerProvider } from "../../src/signer/interface.js";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

function createMockSigner(): SignerProvider {
  const kp = new Ed25519Keypair();
  return {
    getSigner: vi.fn().mockResolvedValue(kp),
    listSigners: vi.fn().mockResolvedValue([
      { address: kp.getPublicKey().toSuiAddress(), label: "test" },
    ]),
  };
}

describe("TxExecutor", () => {
  let db: Database.Database;
  let executor: TxExecutor;
  let mockClient: ReturnType<typeof createMockSuiClient>;
  let gasPool: GasPool;

  beforeEach(async () => {
    db = createDb(":memory:");
    mockClient = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0xGAS", version: "1", digest: "d1", balance: "50000000" },
        ],
        hasNextPage: false,
      }),
      signAndExecuteTransaction: vi.fn().mockResolvedValue({
        digest: "0xTX_DIGEST",
        effects: {
          status: { status: "success" },
          gasUsed: {
            computationCost: "1000",
            storageCost: "500",
            storageRebate: "200",
          },
          mutated: [
            {
              reference: { objectId: "0xGAS", version: "2", digest: "d2" },
            },
          ],
        },
      }),
    });
    gasPool = new GasPool(mockClient, "0xowner", {
      poolSize: 1,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await gasPool.initialize();
    executor = new TxExecutor(mockClient, gasPool, createMockSigner(), db);
  });

  afterEach(() => db.close());

  it("executes a transaction successfully", async () => {
    const tx = new Transaction();
    const result = await executor.execute("test_rule", tx);
    expect(result.success).toBe(true);
    expect(result.digest).toBe("0xTX_DIGEST");
  });

  it("logs transaction to SQLite", async () => {
    const tx = new Transaction();
    await executor.execute("test_rule", tx);
    const logs = db
      .prepare("SELECT * FROM tx_log WHERE rule_name = ?")
      .all("test_rule");
    expect(logs).toHaveLength(1);
  });

  it("releases gas coin back to pool after execution", async () => {
    const tx = new Transaction();
    await executor.execute("test_rule", tx);
    const coin = gasPool.acquire();
    expect(coin).not.toBeNull();
  });

  it("returns failure when no gas coins available", async () => {
    gasPool.acquire(); // exhaust
    const tx = new Transaction();
    const result = await executor.execute("test_rule", tx);
    expect(result.success).toBe(false);
    expect(result.error).toMatch(/no gas coin/i);
  });
});

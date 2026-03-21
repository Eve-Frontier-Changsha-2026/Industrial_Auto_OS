import { describe, it, expect, vi } from "vitest";
import { GasPool } from "../../src/executor/gas-pool.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";

describe("GasPool", () => {
  it("initializes from existing coins", async () => {
    const client = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0x1", version: "1", digest: "d1", balance: "50000000" },
          { coinObjectId: "0x2", version: "2", digest: "d2", balance: "50000000" },
        ],
        hasNextPage: false,
      }),
    });
    const pool = new GasPool(client, "0xowner", {
      poolSize: 2,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await pool.initialize();
    expect(pool.size()).toBe(2);
  });

  it("acquires and releases coins round-robin", async () => {
    const client = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0xA", version: "1", digest: "dA", balance: "50000000" },
          { coinObjectId: "0xB", version: "2", digest: "dB", balance: "50000000" },
        ],
        hasNextPage: false,
      }),
    });
    const pool = new GasPool(client, "0xowner", {
      poolSize: 2,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await pool.initialize();

    const coin1 = pool.acquire();
    expect(coin1?.objectId).toBe("0xA");
    const coin2 = pool.acquire();
    expect(coin2?.objectId).toBe("0xB");
    expect(pool.acquire()).toBeNull();
    pool.release("0xA");
    const coin4 = pool.acquire();
    expect(coin4?.objectId).toBe("0xA");
  });

  it("updates coin ref after TX", async () => {
    const client = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0xA", version: "1", digest: "d1", balance: "50000000" },
        ],
        hasNextPage: false,
      }),
    });
    const pool = new GasPool(client, "0xowner", {
      poolSize: 1,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await pool.initialize();

    pool.updateCoinRef("0xA", { version: "5", digest: "d5", balance: 45000000 });
    const coin = pool.acquire();
    expect(coin?.version).toBe("5");
    expect(coin?.digest).toBe("d5");
    expect(coin?.balance).toBe(45000000);
  });

  it("warns when total balance is low", async () => {
    const client = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0x1", version: "1", digest: "d1", balance: "1000" },
        ],
        hasNextPage: false,
      }),
    });
    const pool = new GasPool(client, "0xowner", {
      poolSize: 1,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await pool.initialize();
    expect(pool.isLowBalance()).toBe(true);
    expect(pool.isCriticalBalance()).toBe(true);
  });
});

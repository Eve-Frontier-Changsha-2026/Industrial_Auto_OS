import { describe, it, expect } from "vitest";
import { ProductionCompleter } from "../../src/rules/production-completer.js";
import type { WatcherSignal } from "../../src/types.js";

describe("ProductionCompleter", () => {
  const handler = new ProductionCompleter("0xCORE");

  it("evaluates true when job is done (RUNNING + jobEnd <= now)", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1", items: new Map(), status: 1, currentJobEnd: 1000, fuelReserve: 100,
      },
    };
    expect(await handler.evaluate(signal, { enabled: true }, 2000)).toBe(true);
  });

  it("evaluates false when job still running", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1", items: new Map(), status: 1, currentJobEnd: 5000, fuelReserve: 100,
      },
    };
    expect(await handler.evaluate(signal, { enabled: true }, 2000)).toBe(false);
  });

  it("evaluates false when line is IDLE", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1", items: new Map(), status: 0, currentJobEnd: 0, fuelReserve: 100,
      },
    };
    expect(await handler.evaluate(signal, { enabled: true }, 2000)).toBe(false);
  });

  it("builds complete_production PTB", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1", items: new Map(), status: 1, currentJobEnd: 1000, fuelReserve: 100,
      },
    };
    const tx = await handler.buildTx(signal, { enabled: true });
    expect(tx).toBeDefined();
  });
});

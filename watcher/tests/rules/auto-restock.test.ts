import { describe, it, expect } from "vitest";
import { AutoRestock } from "../../src/rules/auto-restock.js";
import type { WatcherSignal } from "../../src/types.js";

describe("AutoRestock", () => {
  const handler = new AutoRestock("0xCORE");

  it("evaluates true when material below threshold and IDLE", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: { productionLineId: "0xLINE1", items: new Map([[1, 3]]), status: 0, currentJobEnd: 0, fuelReserve: 100 },
    };
    expect(await handler.evaluate(signal, { enabled: true, threshold: 10, production_line_ids: ["0xLINE1"] })).toBe(true);
  });

  it("evaluates false when all materials above threshold", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: { productionLineId: "0xLINE1", items: new Map([[1, 50]]), status: 0, currentJobEnd: 0, fuelReserve: 100 },
    };
    expect(await handler.evaluate(signal, { enabled: true, threshold: 10, production_line_ids: ["0xLINE1"] })).toBe(false);
  });

  it("evaluates false when line is RUNNING", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: { productionLineId: "0xLINE1", items: new Map([[1, 3]]), status: 1, currentJobEnd: 5000, fuelReserve: 100 },
    };
    expect(await handler.evaluate(signal, { enabled: true, threshold: 10, production_line_ids: ["0xLINE1"] })).toBe(false);
  });
});

import { describe, it, expect } from "vitest";
import { TriggerEvaluator } from "../../src/rules/trigger-evaluator.js";
import type { WatcherSignal } from "../../src/types.js";

describe("TriggerEvaluator", () => {
  it("evaluates true for configured production lines", async () => {
    const handler = new TriggerEvaluator("0xCORE", []);
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: { productionLineId: "0xLINE1", items: new Map([[1, 5]]), status: 0, currentJobEnd: 0, fuelReserve: 100 },
    };
    expect(await handler.evaluate(signal, { enabled: true, production_line_ids: ["0xLINE1"] })).toBe(true);
  });

  it("evaluates false for unconfigured lines", async () => {
    const handler = new TriggerEvaluator("0xCORE", []);
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: { productionLineId: "0xOTHER", items: new Map(), status: 0, currentJobEnd: 0, fuelReserve: 100 },
    };
    expect(await handler.evaluate(signal, { enabled: true, production_line_ids: ["0xLINE1"] })).toBe(false);
  });
});

import { describe, it, expect } from "vitest";
import { FleetDamageHandler } from "../../src/rules/fleet-damage.js";
import type { WatcherSignal } from "../../src/types.js";

const ADDR1 = "0x0000000000000000000000000000000000000000000000000000000000000001";
const ADDR2 = "0x0000000000000000000000000000000000000000000000000000000000000002";
const ADDR3 = "0x0000000000000000000000000000000000000000000000000000000000000003";

describe("FleetDamageHandler", () => {
  const handler = new FleetDamageHandler(ADDR1, ADDR2);

  it("evaluates true for fleet signal with data", async () => {
    const signal: WatcherSignal = {
      type: "fleet",
      fleetData: { recipeId: "0xREC1", quantity: 5, priority: 3, description: "test damage" },
    };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(true);
  });

  it("evaluates false for non-fleet signal", async () => {
    const signal: WatcherSignal = { type: "event" };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(false);
  });

  it("builds create_order_from_damage_report PTB", async () => {
    const signal: WatcherSignal = {
      type: "fleet",
      fleetData: { recipeId: ADDR3, quantity: 5, priority: 3, description: "test damage" },
    };
    const tx = await handler.buildTx(signal, { enabled: true });
    expect(tx).toBeDefined();
  });
});

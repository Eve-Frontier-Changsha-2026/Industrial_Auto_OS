import { describe, it, expect } from "vitest";
import { OrderAcceptor } from "../../src/rules/order-acceptor.js";
import type { WatcherSignal } from "../../src/types.js";

function makeCreatedSignal(escrow: string, recipeId: string): WatcherSignal {
  return {
    type: "event",
    eventData: {
      id: { txDigest: "0x1", eventSeq: "0" },
      type: "0xWO::work_order::WorkOrderCreated",
      parsedJson: { order_id: "0xORDER1", recipe_id: recipeId, escrow_amount: escrow },
      packageId: "0xWO", transactionModule: "work_order", sender: "0x", bcs: "", timestampMs: "0",
    },
  };
}

describe("OrderAcceptor", () => {
  const handler = new OrderAcceptor("0xWO");

  it("accepts when escrow within limit", async () => {
    expect(await handler.evaluate(makeCreatedSignal("1000000000", "0xREC1"), { enabled: true, max_escrow: 5000000000, recipe_ids: [] })).toBe(true);
  });

  it("rejects when escrow exceeds limit", async () => {
    expect(await handler.evaluate(makeCreatedSignal("9999999999", "0xREC1"), { enabled: true, max_escrow: 5000000000, recipe_ids: [] })).toBe(false);
  });

  it("rejects when recipe not in allow list", async () => {
    expect(await handler.evaluate(makeCreatedSignal("1000", "0xBAD"), { enabled: true, max_escrow: 5000000000, recipe_ids: ["0xREC1"] })).toBe(false);
  });
});

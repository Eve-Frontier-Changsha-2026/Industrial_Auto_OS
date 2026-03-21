import { describe, it, expect } from "vitest";
import { OrderCompleter } from "../../src/rules/order-completer.js";
import type { WatcherSignal } from "../../src/types.js";

describe("OrderCompleter", () => {
  const handler = new OrderCompleter("0xWO", "0xBOARD");

  it("evaluates true on WorkOrderDelivered", async () => {
    const signal: WatcherSignal = {
      type: "event",
      eventData: {
        id: { txDigest: "0x1", eventSeq: "0" },
        type: "0xWO::work_order::WorkOrderDelivered",
        parsedJson: { order_id: "0xORDER1" },
        packageId: "0xWO", transactionModule: "work_order", sender: "0x", bcs: "", timestampMs: "0",
      },
    };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(true);
  });

  it("builds complete_work_order PTB", async () => {
    const signal: WatcherSignal = {
      type: "event",
      eventData: {
        id: { txDigest: "0x1", eventSeq: "0" },
        type: "0xWO::work_order::WorkOrderDelivered",
        parsedJson: { order_id: "0xORDER1" },
        packageId: "0xWO", transactionModule: "work_order", sender: "0x", bcs: "", timestampMs: "0",
      },
    };
    const tx = await handler.buildTx(signal, { enabled: true });
    expect(tx).toBeDefined();
  });
});

import { describe, it, expect, vi } from "vitest";
import { DeliveryHandler } from "../../src/rules/delivery-handler.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";
import type { WatcherSignal } from "../../src/types.js";

describe("DeliveryHandler", () => {
  it("evaluates true when auto_deliver is true", async () => {
    const client = createMockSuiClient();
    const handler = new DeliveryHandler("0xWO", client);
    const signal: WatcherSignal = {
      type: "event",
      eventData: {
        id: { txDigest: "0x1", eventSeq: "0" },
        type: "0xWO::work_order::WorkOrderAccepted",
        parsedJson: { order_id: "0xORDER1" },
        packageId: "0xWO", transactionModule: "work_order", sender: "0x", bcs: "", timestampMs: "0",
      },
    };
    expect(await handler.evaluate(signal, { enabled: true, auto_deliver: true })).toBe(true);
  });

  it("evaluates false when auto_deliver is false", async () => {
    const client = createMockSuiClient();
    const handler = new DeliveryHandler("0xWO", client);
    const signal: WatcherSignal = {
      type: "event",
      eventData: {
        id: { txDigest: "0x1", eventSeq: "0" },
        type: "0xWO::work_order::WorkOrderAccepted",
        parsedJson: { order_id: "0xORDER1" },
        packageId: "0xWO", transactionModule: "work_order", sender: "0x", bcs: "", timestampMs: "0",
      },
    };
    expect(await handler.evaluate(signal, { enabled: true, auto_deliver: false })).toBe(false);
  });
});

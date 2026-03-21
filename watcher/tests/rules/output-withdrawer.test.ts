import { describe, it, expect } from "vitest";
import { OutputWithdrawer } from "../../src/rules/output-withdrawer.js";
import type { WatcherSignal } from "../../src/types.js";

function makeCompletedSignal(qty: string): WatcherSignal {
  return {
    type: "event",
    eventData: {
      id: { txDigest: "0x1", eventSeq: "0" },
      type: "0xCORE::production_line::ProductionCompletedEvent",
      parsedJson: { production_line_id: "0xLINE1", output_item_type_id: 42, output_quantity: qty },
      packageId: "0xCORE", transactionModule: "production_line", sender: "0x", bcs: "", timestampMs: "0",
    },
  };
}

describe("OutputWithdrawer", () => {
  const handler = new OutputWithdrawer("0xCORE");

  it("evaluates true on ProductionCompletedEvent with output", async () => {
    expect(await handler.evaluate(makeCompletedSignal("100"), { enabled: true })).toBe(true);
  });

  it("builds withdraw_output PTB", async () => {
    const tx = await handler.buildTx(makeCompletedSignal("100"), { enabled: true });
    expect(tx).toBeDefined();
  });
});

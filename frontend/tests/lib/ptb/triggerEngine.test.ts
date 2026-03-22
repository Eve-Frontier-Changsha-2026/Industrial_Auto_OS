import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";
import { buildCreateTriggerRule, buildToggleTrigger } from "../../../src/lib/ptb/triggerEngine";

describe("triggerEngine PTBs", () => {
  it("buildCreateTriggerRule builds valid tx", () => {
    const tx = buildCreateTriggerRule("0xPKG", "0xLINE", 1, 100, 42, true, 60000);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildToggleTrigger builds valid tx", () => {
    const tx = buildToggleTrigger("0xPKG", "0xRULE", false);
    expect(tx).toBeInstanceOf(Transaction);
  });
});

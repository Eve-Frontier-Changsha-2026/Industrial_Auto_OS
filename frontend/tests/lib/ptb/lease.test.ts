import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";
import { buildCreateLease, buildReturnLease, buildForfeitLease } from "../../../src/lib/ptb/lease";

describe("lease PTBs", () => {
  it("buildCreateLease splits deposit from gas", () => {
    const tx = buildCreateLease("0xPKG", "0xBPO", "0x0000000000000000000000000000000000000000000000000000000000000002", 5000000000n, Date.now() + 86400000 * 30, 100);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildReturnLease builds valid tx", () => {
    const tx = buildReturnLease("0xPKG", "0xLEASE");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildForfeitLease builds valid tx", () => {
    const tx = buildForfeitLease("0xPKG", "0xLEASE");
    expect(tx).toBeInstanceOf(Transaction);
  });
});

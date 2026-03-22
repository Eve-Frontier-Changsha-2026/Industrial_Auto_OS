import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";
import { buildCreateWorkOrder, buildAcceptWorkOrder, buildCompleteWorkOrder, buildCancelWorkOrder } from "../../../src/lib/ptb/workOrder";

const PKG = "0xPKG";

describe("workOrder PTBs", () => {
  it("buildCreateWorkOrder splits escrow from gas", () => {
    const tx = buildCreateWorkOrder(PKG, "0xBOARD", "Fix hull", "0x0000000000000000000000000000000000000000000000000000000000000003", 10, 1000000000n, Date.now() + 86400000, 2);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildAcceptWorkOrder builds valid tx", () => {
    const tx = buildAcceptWorkOrder(PKG, "0xORDER");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildCompleteWorkOrder builds valid tx", () => {
    const tx = buildCompleteWorkOrder(PKG, "0xORDER", "0xBOARD");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildCancelWorkOrder builds valid tx", () => {
    const tx = buildCancelWorkOrder(PKG, "0xORDER", "0xBOARD");
    expect(tx).toBeInstanceOf(Transaction);
  });
});

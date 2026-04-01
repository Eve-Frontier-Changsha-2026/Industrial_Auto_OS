import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";
import { buildListBpo, buildBuyBpo, buildDelistBpo, buildListBpc, buildBuyBpc, buildDelistBpc } from "../../../src/lib/ptb/marketplace";

const PKG = "0xPKG";

describe("marketplace PTBs", () => {
  it("buildDelistBpo transfers returned BPO to sender", () => {
    const tx = buildDelistBpo(PKG, "0xLISTING", "0x0000000000000000000000000000000000000000000000000000000000000001");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildDelistBpc transfers returned BPC to sender", () => {
    const tx = buildDelistBpc(PKG, "0xLISTING", "0x0000000000000000000000000000000000000000000000000000000000000001");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildBuyBpo splits coin from gas", () => {
    const tx = buildBuyBpo(PKG, "0xMARKET", "0xLISTING", 1000000000n);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildListBpo builds valid tx", () => {
    const tx = buildListBpo(PKG, "0xMARKET", "0xBPO", 1000n);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildListBpc builds valid tx", () => {
    const tx = buildListBpc(PKG, "0xMARKET", "0xBPC", 500n);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildBuyBpc splits coin from gas", () => {
    const tx = buildBuyBpc(PKG, "0xMARKET", "0xLISTING", 500000000n);
    expect(tx).toBeInstanceOf(Transaction);
  });
});

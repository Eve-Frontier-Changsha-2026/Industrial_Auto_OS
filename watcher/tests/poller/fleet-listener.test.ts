import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { FleetListener } from "../../src/poller/fleet-listener.js";

describe("FleetListener", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("generates mock damage reports on interval", () => {
    const reports: any[] = [];
    const listener = new FleetListener({
      mock: true,
      intervalMs: 5000,
      recipeIds: ["0xREC1", "0xREC2"],
      onReport: (r) => reports.push(r),
    });
    listener.start();
    vi.advanceTimersByTime(5000);
    expect(reports).toHaveLength(1);
    expect(reports[0].recipeId).toMatch(/^0xREC/);

    vi.advanceTimersByTime(5000);
    expect(reports).toHaveLength(2);
    listener.stop();
  });

  it("does nothing when mock is false", () => {
    const reports: any[] = [];
    const listener = new FleetListener({
      mock: false,
      intervalMs: 5000,
      recipeIds: ["0xREC1"],
      onReport: (r) => reports.push(r),
    });
    listener.start();
    vi.advanceTimersByTime(10000);
    expect(reports).toHaveLength(0);
    listener.stop();
  });
});

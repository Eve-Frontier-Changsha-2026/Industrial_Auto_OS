import { describe, it, expect } from "vitest";
import { ExpiredCleaner } from "../../src/rules/expired-cleaner.js";
import type { WatcherSignal } from "../../src/types.js";

describe("ExpiredCleaner", () => {
  const handler = new ExpiredCleaner("0xWO", "0xBOARD");

  it("evaluates true for expire deadline", async () => {
    const signal: WatcherSignal = {
      type: "deadline",
      deadlineData: { id: 1, objectId: "0xORDER1", objectType: "work_order", deadlineType: "expire", deadlineAt: 1000 },
    };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(true);
  });

  it("evaluates false for non-expire deadline", async () => {
    const signal: WatcherSignal = {
      type: "deadline",
      deadlineData: { id: 2, objectId: "0xORDER1", objectType: "work_order", deadlineType: "auto_complete", deadlineAt: 1000 },
    };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(false);
  });
});

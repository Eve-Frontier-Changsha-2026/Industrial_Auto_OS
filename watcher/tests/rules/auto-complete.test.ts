import { describe, it, expect } from "vitest";
import { AutoComplete } from "../../src/rules/auto-complete.js";
import type { WatcherSignal } from "../../src/types.js";

describe("AutoComplete", () => {
  const handler = new AutoComplete("0xWO", "0xBOARD");

  it("evaluates true for auto_complete deadline", async () => {
    const signal: WatcherSignal = {
      type: "deadline",
      deadlineData: { id: 1, objectId: "0xORDER1", objectType: "work_order", deadlineType: "auto_complete", deadlineAt: 1000 },
    };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(true);
  });

  it("evaluates false for other deadline types", async () => {
    const signal: WatcherSignal = {
      type: "deadline",
      deadlineData: { id: 2, objectId: "0xORDER1", objectType: "work_order", deadlineType: "expire", deadlineAt: 1000 },
    };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(false);
  });
});

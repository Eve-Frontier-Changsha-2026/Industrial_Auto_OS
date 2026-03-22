import { describe, it, expect } from "vitest";
import { CLOCK_ID, TYPE_STRINGS } from "../../src/lib/constants";

describe("constants", () => {
  it("has correct clock ID", () => {
    expect(CLOCK_ID).toBe("0x6");
  });

  it("TYPE_STRINGS produce correct module paths", () => {
    const pkg = "0xABC";
    expect(TYPE_STRINGS.BlueprintOriginal(pkg)).toBe("0xABC::blueprint::BlueprintOriginal");
    expect(TYPE_STRINGS.WorkOrder(pkg)).toBe("0xABC::work_order::WorkOrder");
  });
});

import { describe, it, expect } from "vitest";
import { humanError } from "../../src/lib/errors";

describe("errors", () => {
  it("maps known Move error codes", () => {
    expect(humanError(0)).toBe("Not owner");
    expect(humanError(100)).toBe("Insufficient escrow");
    expect(humanError(204)).toBe("Listing inactive");
  });

  it("returns generic message for unknown codes", () => {
    expect(humanError(9999)).toContain("9999");
  });
});

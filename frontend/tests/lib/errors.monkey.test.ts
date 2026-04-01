/**
 * Monkey / extreme tests for errors.ts
 * Goal: break humanError, probe for XSS-able error messages
 */
import { describe, it, expect } from "vitest";
import { humanError } from "../../src/lib/errors";

describe("humanError — monkey tests", () => {
  it("known code returns correct message", () => {
    expect(humanError(0)).toBe("Not owner");
    expect(humanError(200)).toBe("Listing price too low");
    expect(humanError(2013)).toBe("Not authorized — only factory owner");
  });

  it("unknown positive code", () => {
    expect(humanError(9999)).toBe("Unknown error (code: 9999)");
  });

  it("negative code", () => {
    expect(humanError(-1)).toBe("Unknown error (code: -1)");
  });

  it("zero (boundary — this IS a valid code)", () => {
    expect(humanError(0)).toBe("Not owner");
  });

  it("NaN", () => {
    const result = humanError(NaN);
    expect(result).toBe("Unknown error (code: NaN)");
  });

  it("Infinity", () => {
    expect(humanError(Infinity)).toBe("Unknown error (code: Infinity)");
  });

  it("MAX_SAFE_INTEGER", () => {
    const result = humanError(Number.MAX_SAFE_INTEGER);
    expect(result).toContain("Unknown error");
  });

  it("float rounds to lookup", () => {
    // 0.0 should hit code 0
    expect(humanError(0.0)).toBe("Not owner");
    // 0.5 — Record key coerces to "0.5", won't match
    expect(humanError(0.5)).toContain("Unknown error");
  });

  it("error messages don't contain HTML (XSS check)", () => {
    // 確認所有 error message 不含 <script>, <img>, on* 等 XSS vectors
    const htmlPattern = /<\s*\/?\s*(script|img|iframe|svg|on\w+)/i;
    for (let code = 0; code <= 2100; code++) {
      const msg = humanError(code);
      expect(msg, `code ${code} contains HTML`).not.toMatch(htmlPattern);
    }
  });

  it("error message template injection", () => {
    // 如果有人 patch ERROR_MAP 注入 ${} 模板，humanError 應該原樣輸出
    // 這裡測 fallback path
    const result = humanError(99999);
    expect(result).toBe("Unknown error (code: 99999)");
    // 確認 code 不被當成 template literal 執行
    expect(result).not.toContain("undefined");
  });
});

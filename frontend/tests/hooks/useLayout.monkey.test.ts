/**
 * Monkey / extreme tests for useLayout
 * Goal: localStorage injection, JSON bomb, schema corruption
 */
import { describe, it, expect, beforeEach } from "vitest";
import { saveLayout, loadLayout, STORAGE_KEY } from "../../src/hooks/useLayout";

describe("useLayout — monkey tests", () => {
  beforeEach(() => localStorage.clear());

  // ────── localStorage injection ──────

  it("JSON with extra malicious fields (prototype pollution attempt)", () => {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify([{ i: "x", x: 0, y: 0, w: 1, h: 1, __proto__: { admin: true } }]),
    );
    const result = loadLayout();
    expect(result).not.toBeNull();
    expect((result as any).admin).toBeUndefined();
  });

  it("nested object instead of array → rejected by schema validation", () => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ i: "x", x: 0 }));
    const result = loadLayout();
    expect(result).toBeNull(); // FIXED: schema validation rejects non-array
  });

  it("array with null elements → rejected by schema validation", () => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify([null, null, null]));
    const result = loadLayout();
    expect(result).toBeNull(); // FIXED: null items fail type check
  });

  it("array with wrong types (numbers instead of objects) → rejected", () => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify([1, 2, 3]));
    const result = loadLayout();
    expect(result).toBeNull(); // FIXED: numbers fail item validation
  });

  it("extremely large array (100K items) — memory bomb", () => {
    const huge = Array.from({ length: 100_000 }, (_, i) => ({
      i: `pane-${i}`, x: i % 24, y: Math.floor(i / 24), w: 1, h: 1,
    }));
    localStorage.setItem(STORAGE_KEY, JSON.stringify(huge));
    const result = loadLayout();
    expect(result).toHaveLength(100_000);
  });

  it("valid JSON but empty array → rejected (needs items)", () => {
    localStorage.setItem(STORAGE_KEY, "[]");
    const result = loadLayout();
    expect(result).toBeNull(); // FIXED: empty array fails isLayoutArray check
  });

  it("string 'null'", () => {
    localStorage.setItem(STORAGE_KEY, "null");
    const result = loadLayout();
    expect(result).toBeNull();
  });

  it("string 'undefined' (invalid JSON)", () => {
    localStorage.setItem(STORAGE_KEY, "undefined");
    const result = loadLayout();
    expect(result).toBeNull(); // JSON.parse("undefined") throws → catch → null
  });

  it("XSS payload in item id", () => {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify([{
        i: '<img src=x onerror="alert(1)">',
        x: 0, y: 0, w: 6, h: 4,
      }]),
    );
    const result = loadLayout();
    expect(result![0].i).toContain("<img"); // Stored as-is → if rendered as HTML = XSS
  });

  it("negative coordinates", () => {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify([{ i: "a", x: -100, y: -200, w: -1, h: -1 }]),
    );
    const result = loadLayout();
    expect(result![0].x).toBe(-100); // No validation → react-grid-layout behavior undefined
  });

  it("NaN/Infinity in coordinates → null after JSON round-trip → rejected", () => {
    // JSON.stringify converts NaN/Infinity to null, null fails typeof === 'number'
    const data = [{ i: "a", x: null, y: null, w: null, h: null }];
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    const result = loadLayout();
    expect(result).toBeNull(); // FIXED: null coords rejected by schema
  });

  it("very large coordinate values", () => {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify([{ i: "a", x: Number.MAX_SAFE_INTEGER, y: Number.MAX_SAFE_INTEGER, w: 1e10, h: 1e10 }]),
    );
    const result = loadLayout();
    expect(result).not.toBeNull();
  });

  // ────── saveLayout edge cases ──────

  it("save empty array → load returns null (empty layout rejected)", () => {
    saveLayout([]);
    expect(loadLayout()).toBeNull(); // FIXED: empty array rejected by schema
  });

  it("save round-trips special characters in id", () => {
    const layout = [{ i: '"; DROP TABLE users;--', x: 0, y: 0, w: 1, h: 1 } as any];
    saveLayout(layout);
    const result = loadLayout();
    expect(result![0].i).toBe('"; DROP TABLE users;--');
  });

  it("save with circular reference (if accidentally passed)", () => {
    const item: any = { i: "a", x: 0, y: 0, w: 1, h: 1 };
    item.self = item; // circular
    expect(() => saveLayout([item])).toThrow(); // JSON.stringify throws on circular
  });
});

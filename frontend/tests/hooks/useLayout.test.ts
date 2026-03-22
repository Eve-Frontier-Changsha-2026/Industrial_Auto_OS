import { describe, it, expect, beforeEach } from "vitest";
import { saveLayout, loadLayout, STORAGE_KEY } from "../../src/hooks/useLayout";
import type { LayoutItem } from "react-grid-layout";

describe("useLayout persistence", () => {
  beforeEach(() => localStorage.clear());

  it("returns null when no saved layout", () => {
    expect(loadLayout()).toBeNull();
  });

  it("round-trips layout to localStorage", () => {
    const layout: LayoutItem[] = [{ i: "system-overview", x: 0, y: 0, w: 6, h: 4 }];
    saveLayout(layout);
    expect(loadLayout()).toEqual(layout);
  });

  it("returns null for corrupted data", () => {
    localStorage.setItem(STORAGE_KEY, "not-json");
    expect(loadLayout()).toBeNull();
  });
});

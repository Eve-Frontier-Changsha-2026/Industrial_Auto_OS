import { describe, it, expect } from "vitest";
import { getDefaultPanes, addPane, removePane, toggleMinimize } from "../../src/hooks/usePaneManager";

describe("usePaneManager", () => {
  it("returns default pane set", () => {
    const panes = getDefaultPanes();
    expect(panes).toContain("system-overview");
    expect(panes).toContain("production-monitor");
    expect(panes).toContain("activity-feed");
  });

  it("addPane adds pane ID to set", () => {
    const panes = new Set(["a"]);
    expect(addPane(panes, "b")).toEqual(new Set(["a", "b"]));
  });

  it("removePane removes pane ID", () => {
    const panes = new Set(["a", "b"]);
    expect(removePane(panes, "a")).toEqual(new Set(["b"]));
  });

  it("toggleMinimize flips state", () => {
    const mins = new Set<string>();
    expect(toggleMinimize(mins, "a")).toEqual(new Set(["a"]));
    expect(toggleMinimize(new Set(["a"]), "a")).toEqual(new Set());
  });
});

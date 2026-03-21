import { describe, it, expect } from "vitest";
import { RuleRegistry } from "../../src/rules/registry.js";
import type { RuleHandler } from "../../src/rules/interface.js";
import { Transaction } from "@mysten/sui/transactions";

function makeStubRule(
  overrides: Partial<RuleHandler> = {},
): RuleHandler {
  return {
    name: "stub",
    description: "stub rule",
    enabled: true,
    evaluate: async () => true,
    buildTx: async () => new Transaction(),
    ...overrides,
  };
}

describe("RuleRegistry", () => {
  it("registers and retrieves by event type", () => {
    const registry = new RuleRegistry();
    registry.register(
      makeStubRule({
        name: "r1",
        eventType: "ProductionCompletedEvent",
      }),
    );
    const found = registry.getByEventType(
      "0xPKG::production_line::ProductionCompletedEvent",
    );
    expect(found).toHaveLength(1);
    expect(found[0].name).toBe("r1");
  });

  it("registers and retrieves by schedule type", () => {
    const registry = new RuleRegistry();
    registry.register(
      makeStubRule({ name: "r2", scheduleType: "inventory" }),
    );
    expect(registry.getByScheduleType("inventory")).toHaveLength(1);
  });

  it("lists all registered rules", () => {
    const registry = new RuleRegistry();
    registry.register(makeStubRule({ name: "a" }));
    registry.register(makeStubRule({ name: "b" }));
    expect(registry.listAll()).toHaveLength(2);
  });

  it("skips disabled rules in queries", () => {
    const registry = new RuleRegistry();
    registry.register(
      makeStubRule({
        name: "off",
        eventType: "T",
        enabled: false,
      }),
    );
    expect(registry.getByEventType("T")).toHaveLength(0);
  });
});

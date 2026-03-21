import { describe, it, expect } from "vitest";
import { LeaseForfeiter } from "../../src/rules/lease-forfeiter.js";
import type { WatcherSignal } from "../../src/types.js";

describe("LeaseForfeiter", () => {
  const handler = new LeaseForfeiter("0xMKT");

  it("evaluates true for lease_forfeit deadline", async () => {
    const signal: WatcherSignal = {
      type: "deadline",
      deadlineData: { id: 1, objectId: "0xLEASE1", objectType: "lease", deadlineType: "lease_forfeit", deadlineAt: 1000 },
    };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(true);
  });

  it("evaluates false for non-lease deadlines", async () => {
    const signal: WatcherSignal = {
      type: "deadline",
      deadlineData: { id: 2, objectId: "0xORDER1", objectType: "work_order", deadlineType: "expire", deadlineAt: 1000 },
    };
    expect(await handler.evaluate(signal, { enabled: true })).toBe(false);
  });

  it("builds forfeit_lease PTB", async () => {
    const signal: WatcherSignal = {
      type: "deadline",
      deadlineData: { id: 1, objectId: "0xLEASE1", objectType: "lease", deadlineType: "lease_forfeit", deadlineAt: 1000 },
    };
    const tx = await handler.buildTx(signal, { enabled: true });
    expect(tx).toBeDefined();
  });
});

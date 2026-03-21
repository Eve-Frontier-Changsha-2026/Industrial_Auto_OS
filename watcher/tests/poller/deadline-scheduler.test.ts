import { describe, it, expect, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import { DeadlineScheduler } from "../../src/poller/deadline-scheduler.js";
import { createDb, upsertDeadline } from "../../src/db/sqlite.js";
import type { SuiEvent } from "@mysten/sui/client";

function makeEvent(type: string, parsedJson: any, timestampMs = "0"): SuiEvent {
  return {
    id: { txDigest: "0x1", eventSeq: "0" },
    type,
    parsedJson,
    packageId: "0xPKG",
    transactionModule: "m",
    sender: "0x",
    bcs: "",
    timestampMs,
  };
}

describe("DeadlineScheduler", () => {
  let db: Database.Database;
  let scheduler: DeadlineScheduler;

  beforeEach(() => {
    db = createDb(":memory:");
    scheduler = new DeadlineScheduler(db);
  });
  afterEach(() => db.close());

  it("extracts deadline from WorkOrderCreated", () => {
    scheduler.processEvents([
      makeEvent("0xPKG::work_order::WorkOrderCreated", {
        order_id: "0xORDER1",
        deadline: "1711000000000",
      }),
    ]);
    const rows = db.prepare("SELECT * FROM deadlines").all();
    expect(rows).toHaveLength(1);
    expect((rows[0] as any).object_id).toBe("0xORDER1");
    expect((rows[0] as any).deadline_type).toBe("expire");
  });

  it("extracts deadline from LeaseCreated", () => {
    scheduler.processEvents([
      makeEvent("0xPKG::lease::LeaseCreated", {
        lease_id: "0xLEASE1",
        expiry: "1711500000000",
      }),
    ]);
    const rows = db
      .prepare("SELECT * FROM deadlines WHERE deadline_type = 'lease_forfeit'")
      .all();
    expect(rows).toHaveLength(1);
  });

  it("returns expired deadlines", () => {
    upsertDeadline(db, {
      objectId: "0xORDER1",
      objectType: "work_order",
      deadlineType: "expire",
      deadlineAt: 1000,
    });
    upsertDeadline(db, {
      objectId: "0xORDER2",
      objectType: "work_order",
      deadlineType: "expire",
      deadlineAt: 5000,
    });
    const expired = scheduler.getExpired(3000);
    expect(expired).toHaveLength(1);
    expect(expired[0].objectId).toBe("0xORDER1");
  });

  it("creates auto_complete deadline on WorkOrderAccepted", () => {
    scheduler.processEvents([
      makeEvent(
        "0xPKG::work_order::WorkOrderAccepted",
        { order_id: "0xORDER3" },
        "1710000000000",
      ),
    ]);
    const rows = db
      .prepare("SELECT * FROM deadlines WHERE deadline_type = 'auto_complete'")
      .all();
    expect(rows).toHaveLength(1);
    expect((rows[0] as any).deadline_at).toBe(
      1710000000000 + 72 * 60 * 60 * 1000,
    );
  });
});

import type Database from "better-sqlite3";
import type { SuiEvent } from "@mysten/sui/client";
import {
  upsertDeadline,
  getExpiredDeadlines,
  markDeadlineProcessed,
} from "../db/sqlite.js";
import type { DeadlineRecord } from "../types.js";

const AUTO_COMPLETE_DELAY_MS = 72 * 60 * 60 * 1000; // 72 hours

export class DeadlineScheduler {
  constructor(private db: Database.Database) {}

  processEvents(events: SuiEvent[]): void {
    for (const event of events) {
      const parsed = event.parsedJson as Record<string, any>;
      const eventType = event.type.split("::").pop() ?? "";

      switch (eventType) {
        case "WorkOrderCreated":
          upsertDeadline(this.db, {
            objectId: parsed.order_id,
            objectType: "work_order",
            deadlineType: "expire",
            deadlineAt: Number(parsed.deadline),
          });
          break;

        case "WorkOrderAccepted":
          upsertDeadline(this.db, {
            objectId: parsed.order_id,
            objectType: "work_order",
            deadlineType: "auto_complete",
            deadlineAt:
              Number(event.timestampMs) + AUTO_COMPLETE_DELAY_MS,
          });
          break;

        case "LeaseCreated":
          upsertDeadline(this.db, {
            objectId: parsed.lease_id,
            objectType: "lease",
            deadlineType: "lease_forfeit",
            deadlineAt: Number(parsed.expiry),
          });
          break;

        case "WorkOrderCompleted":
        case "WorkOrderCancelled":
          this.markAllForObject(parsed.order_id);
          break;

        case "LeaseReturned":
        case "LeaseForfeited":
          this.markAllForObject(parsed.lease_id);
          break;
      }
    }
  }

  getExpired(now: number): (DeadlineRecord & { id: number })[] {
    return getExpiredDeadlines(this.db, now);
  }

  markProcessed(id: number): void {
    markDeadlineProcessed(this.db, id);
  }

  private markAllForObject(objectId: string): void {
    this.db
      .prepare(
        "UPDATE deadlines SET processed = 1 WHERE object_id = ? AND processed = 0",
      )
      .run(objectId);
  }
}

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import {
  createDb,
  getCursor,
  setCursor,
  insertTxLog,
  getExpiredDeadlines,
  upsertDeadline,
  markDeadlineProcessed,
} from "../../src/db/sqlite.js";

describe("SQLite DB", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = createDb(":memory:");
  });
  afterEach(() => {
    db.close();
  });

  describe("cursors", () => {
    it("returns null for missing cursor", () => {
      expect(getCursor(db, "test_event")).toBeNull();
    });

    it("sets and gets cursor", () => {
      setCursor(db, "test_event", "cursor_123");
      expect(getCursor(db, "test_event")).toBe("cursor_123");
    });

    it("upserts cursor on conflict", () => {
      setCursor(db, "test_event", "cursor_1");
      setCursor(db, "test_event", "cursor_2");
      expect(getCursor(db, "test_event")).toBe("cursor_2");
    });
  });

  describe("tx_log", () => {
    it("inserts and retrieves tx log", () => {
      const id = insertTxLog(db, {
        ruleName: "auto_restock",
        txDigest: "0xabc",
        status: "success",
        error: null,
        signalData: '{"type":"inventory"}',
        gasCoinId: "0x111",
        gasUsed: 5000,
        createdAt: Date.now(),
      });
      expect(id).toBeGreaterThan(0);
    });
  });

  describe("deadlines", () => {
    it("upserts deadline with composite key", () => {
      upsertDeadline(db, {
        objectId: "0xorder1",
        objectType: "work_order",
        deadlineType: "auto_complete",
        deadlineAt: 1000,
      });
      upsertDeadline(db, {
        objectId: "0xorder1",
        objectType: "work_order",
        deadlineType: "expire",
        deadlineAt: 2000,
      });
      const expired = getExpiredDeadlines(db, 1500);
      expect(expired).toHaveLength(1);
      expect(expired[0].deadlineType).toBe("auto_complete");
    });

    it("marks deadline as processed", () => {
      upsertDeadline(db, {
        objectId: "0xorder1",
        objectType: "work_order",
        deadlineType: "expire",
        deadlineAt: 1000,
      });
      const before = getExpiredDeadlines(db, 2000);
      expect(before).toHaveLength(1);
      markDeadlineProcessed(db, before[0].id);
      const after = getExpiredDeadlines(db, 2000);
      expect(after).toHaveLength(0);
    });
  });

  describe("atomic cursor + tx_log", () => {
    it("writes cursor and tx_log atomically", () => {
      const atomicWrite = db.transaction(() => {
        setCursor(db, "package_events", "cursor_99");
        insertTxLog(db, {
          ruleName: "output_withdrawer",
          txDigest: "0xdef",
          status: "success",
          error: null,
          signalData: null,
          gasCoinId: "0x222",
          gasUsed: 3000,
          createdAt: Date.now(),
        });
      });
      atomicWrite();
      expect(getCursor(db, "package_events")).toBe("cursor_99");
    });
  });
});

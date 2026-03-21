import Database from "better-sqlite3";
import { runMigrations } from "./migrations.js";
import type { TxLogEntry, DeadlineRecord } from "../types.js";

export function createDb(path: string): Database.Database {
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  runMigrations(db);
  return db;
}

export function getCursor(
  db: Database.Database,
  eventType: string,
): string | null {
  const row = db
    .prepare("SELECT cursor_id FROM cursors WHERE event_type = ?")
    .get(eventType) as { cursor_id: string } | undefined;
  return row?.cursor_id ?? null;
}

export function setCursor(
  db: Database.Database,
  eventType: string,
  cursorId: string,
): void {
  db.prepare(
    `INSERT INTO cursors (event_type, cursor_id, updated_at)
     VALUES (?, ?, ?)
     ON CONFLICT(event_type) DO UPDATE SET
       cursor_id = excluded.cursor_id,
       updated_at = excluded.updated_at`,
  ).run(eventType, cursorId, Date.now());
}

export function insertTxLog(
  db: Database.Database,
  entry: Omit<TxLogEntry, "id">,
): number {
  const result = db
    .prepare(
      `INSERT INTO tx_log
       (rule_name, tx_digest, status, error, signal_data, gas_coin_id, gas_used, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(
      entry.ruleName,
      entry.txDigest,
      entry.status,
      entry.error,
      entry.signalData,
      entry.gasCoinId,
      entry.gasUsed,
      entry.createdAt,
    );
  return Number(result.lastInsertRowid);
}

interface DeadlineInsert {
  objectId: string;
  objectType: string;
  deadlineType: string;
  deadlineAt: number;
}

export function upsertDeadline(
  db: Database.Database,
  d: DeadlineInsert,
): void {
  db.prepare(
    `INSERT INTO deadlines (object_id, object_type, deadline_type, deadline_at, created_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(object_id, deadline_type) DO UPDATE SET
       deadline_at = excluded.deadline_at`,
  ).run(d.objectId, d.objectType, d.deadlineType, d.deadlineAt, Date.now());
}

export function getExpiredDeadlines(
  db: Database.Database,
  now: number,
): (DeadlineRecord & { id: number })[] {
  return db
    .prepare(
      `SELECT id,
              object_id     AS objectId,
              object_type   AS objectType,
              deadline_type AS deadlineType,
              deadline_at   AS deadlineAt
       FROM deadlines
       WHERE deadline_at <= ? AND processed = 0
       ORDER BY deadline_at`,
    )
    .all(now) as (DeadlineRecord & { id: number })[];
}

export function markDeadlineProcessed(
  db: Database.Database,
  id: number,
): void {
  db.prepare("UPDATE deadlines SET processed = 1 WHERE id = ?").run(id);
}

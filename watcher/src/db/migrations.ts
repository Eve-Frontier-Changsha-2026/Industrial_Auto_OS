import type Database from "better-sqlite3";

export function runMigrations(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS cursors (
      event_type TEXT PRIMARY KEY,
      cursor_id  TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS tx_log (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      rule_name   TEXT NOT NULL,
      tx_digest   TEXT,
      status      TEXT NOT NULL,
      error       TEXT,
      signal_data TEXT,
      gas_coin_id TEXT,
      gas_used    INTEGER,
      created_at  INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS deadlines (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      object_id     TEXT NOT NULL,
      object_type   TEXT NOT NULL,
      deadline_type TEXT NOT NULL,
      deadline_at   INTEGER NOT NULL,
      processed     INTEGER NOT NULL DEFAULT 0,
      created_at    INTEGER NOT NULL,
      UNIQUE(object_id, deadline_type)
    );

    CREATE INDEX IF NOT EXISTS idx_deadlines_pending
      ON deadlines(deadline_at) WHERE processed = 0;
  `);
}

# Off-chain Watcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Node.js long-running process that polls SUI on-chain events/state and auto-executes transactions against Industrial Auto OS contracts.

**Architecture:** Plugin-ready watcher engine with EventPoller, InventoryMonitor, DeadlineScheduler, and FleetCmdListener feeding signals through a RuleRegistry/Dispatcher to 11 RuleHandlers. TxExecutor manages gas pool (20 pre-split coins, round-robin) and retry logic. SQLite persists cursors, tx logs, and deadlines with atomic dedup.

**Tech Stack:** TypeScript, Node.js, @mysten/sui, better-sqlite3, yaml, vitest

**Spec:** `docs/superpowers/specs/2026-03-21-offchain-watcher-design.md`

---

## File Structure

```
watcher/
├── src/
│   ├── index.ts                    # CLI entry point
│   ├── engine.ts                   # WatcherEngine orchestrator
│   ├── config.ts                   # YAML loader + validation
│   ├── types.ts                    # Shared interfaces (WatcherSignal, RuleConfig, etc.)
│   ├── signer/
│   │   ├── interface.ts            # SignerProvider interface
│   │   └── single.ts              # SingleKeypairProvider (keystore file)
│   ├── poller/
│   │   ├── event-poller.ts        # SUI event polling + cursor persistence
│   │   ├── inventory-monitor.ts   # Production line buffer check via getDynamicFieldObject
│   │   ├── deadline-scheduler.ts  # Deadline-based triggers + startup backfill
│   │   └── fleet-listener.ts      # Mock fleet damage reports
│   ├── rules/
│   │   ├── interface.ts           # RuleHandler interface
│   │   ├── registry.ts            # RuleRegistry (register + lookup)
│   │   ├── trigger-evaluator.ts   # Polls TriggerRule objects
│   │   ├── output-withdrawer.ts   # Withdraw completed production output
│   │   ├── auto-restock.ts        # Start production when inventory low
│   │   ├── order-acceptor.ts      # Accept matching work orders
│   │   ├── order-completer.ts     # Complete delivered orders (issuer)
│   │   ├── auto-complete.ts       # Auto-complete after 72h (acceptor)
│   │   ├── expired-cleaner.ts     # Cancel expired orders (permissionless)
│   │   ├── lease-forfeiter.ts     # Forfeit expired leases (lessor)
│   │   ├── fleet-damage.ts        # Create order from damage report
│   │   ├── production-completer.ts # Complete finished production jobs
│   │   └── delivery-handler.ts    # Deliver for accepted orders
│   ├── executor/
│   │   ├── tx-executor.ts         # Sign + submit + retry + logging
│   │   ├── ptb-builder.ts         # moveCall wrappers for each contract function
│   │   └── gas-pool.ts            # Coin split/merge/round-robin
│   └── db/
│       ├── sqlite.ts              # Connection + query helpers
│       └── migrations.ts          # Schema creation (cursors, tx_log, deadlines)
├── tests/
│   ├── helpers/
│   │   └── mock-sui-client.ts     # Mock SuiClient for unit tests
│   ├── db/
│   │   └── sqlite.test.ts
│   ├── config.test.ts
│   ├── signer/
│   │   └── single.test.ts
│   ├── executor/
│   │   ├── gas-pool.test.ts
│   │   └── tx-executor.test.ts
│   ├── poller/
│   │   ├── event-poller.test.ts
│   │   ├── inventory-monitor.test.ts
│   │   ├── deadline-scheduler.test.ts
│   │   └── fleet-listener.test.ts
│   ├── rules/
│   │   ├── registry.test.ts
│   │   ├── trigger-evaluator.test.ts
│   │   ├── output-withdrawer.test.ts
│   │   ├── auto-restock.test.ts
│   │   ├── order-acceptor.test.ts
│   │   ├── order-completer.test.ts
│   │   ├── auto-complete.test.ts
│   │   ├── expired-cleaner.test.ts
│   │   ├── lease-forfeiter.test.ts
│   │   ├── fleet-damage.test.ts
│   │   ├── production-completer.test.ts
│   │   └── delivery-handler.test.ts
│   └── engine.test.ts
├── config.example.yaml
├── package.json
├── tsconfig.json
└── vitest.config.ts
```

**Conventions:**
- All paths below are relative to `watcher/` unless stated otherwise
- `ROOT` = project root (Industrial_Auto_OS)
- Contract source at `ROOT/packages/{industrial_core,work_order,marketplace}/sources/`
- Use `@mysten/sui` v1.x (`SuiClient`, `Transaction`, `Ed25519Keypair`)
- Use `better-sqlite3` (sync API — simpler for single-process watcher)
- Use `vitest` for testing
- Use `yaml` package for config parsing

---

### Task 1: Project Scaffold

**Files:**
- Create: `watcher/package.json`
- Create: `watcher/tsconfig.json`
- Create: `watcher/vitest.config.ts`
- Create: `watcher/config.example.yaml`

- [ ] **Step 1: Create watcher directory and package.json**

```json
{
  "name": "industrial-auto-os-watcher",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx src/index.ts",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@mysten/sui": "^1.21.0",
    "better-sqlite3": "^11.8.0",
    "yaml": "^2.7.0"
  },
  "devDependencies": {
    "@types/better-sqlite3": "^7.6.13",
    "@types/node": "^22.0.0",
    "tsx": "^4.19.0",
    "typescript": "^5.7.0",
    "vitest": "^3.0.0"
  }
}
```

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true,
    "sourceMap": true,
    "resolveJsonModule": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

- [ ] **Step 3: Create vitest.config.ts**

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: ["tests/**/*.test.ts"],
    testTimeout: 10_000,
  },
});
```

- [ ] **Step 4: Create config.example.yaml**

Copy the YAML from spec verbatim — all fields with placeholder `"0x..."` values.

- [ ] **Step 5: Install dependencies**

Run: `cd watcher && npm install`
Expected: `node_modules/` created, no errors

- [ ] **Step 6: Verify typecheck**

Run: `cd watcher && npx tsc --noEmit`
Expected: No errors (no source files yet)

- [ ] **Step 7: Commit**

```bash
git add watcher/package.json watcher/tsconfig.json watcher/vitest.config.ts watcher/config.example.yaml watcher/package-lock.json
git commit -m "feat(watcher): scaffold project with deps"
```

---

### Task 2: Types & Interfaces

**Files:**
- Create: `src/types.ts`
- Create: `src/rules/interface.ts`
- Create: `src/signer/interface.ts`

- [ ] **Step 1: Create src/types.ts with all shared types**

```ts
import type { SuiEvent } from "@mysten/sui/client";

// ─── Signal Types ───────────────────────────────

export interface WatcherSignal {
  type: "event" | "inventory" | "deadline" | "fleet";
  eventData?: SuiEvent;
  inventoryData?: InventorySnapshot;
  deadlineData?: DeadlineRecord;
  fleetData?: MockDamageReport;
}

export interface InventorySnapshot {
  productionLineId: string;
  items: Map<number, number>; // item_type_id -> quantity
  status: number; // 0=IDLE, 1=RUNNING
  currentJobEnd: number; // timestamp ms, 0 if idle
  fuelReserve: number;
}

export interface DeadlineRecord {
  id: number;
  objectId: string;
  objectType: "work_order" | "lease";
  deadlineType: "deliver" | "auto_complete" | "expire" | "lease_forfeit";
  deadlineAt: number; // timestamp ms
}

export interface MockDamageReport {
  recipeId: string;
  quantity: number;
  priority: number;
  description: string;
}

// ─── Config Types ───────────────────────────────

export interface WatcherConfig {
  network: "devnet" | "testnet" | "mainnet";
  package_ids: {
    industrial_core: string;
    work_order: string;
    marketplace: string;
  };
  signer: {
    type: "single";
    keypath: string;
  };
  watch: {
    poll_interval_ms: number;
    production_line_ids: string[];
    work_order_board_id: string;
    marketplace_id: string;
    item_type_ids: number[];  // u32 Bag keys matching on-chain input_buffer
  };
  gas: {
    pool_size: number;
    min_balance_warn: number;
    min_coin_balance: number;
    auto_replenish: boolean;
  };
  rules: Record<string, RuleConfig>;
}

export interface RuleConfig {
  enabled: boolean;
  [key: string]: unknown;
}

// ─── Gas Pool Types ─────────────────────────────

export interface GasCoinEntry {
  objectId: string;
  version: string;
  digest: string;
  balance: number;
}

// ─── TX Log Types ───────────────────────────────

export type TxStatus = "success" | "failed" | "retrying";

export interface TxLogEntry {
  id?: number;
  ruleName: string;
  txDigest: string | null;
  status: TxStatus;
  error: string | null;
  signalData: string | null;
  gasCoinId: string | null;
  gasUsed: number | null;
  createdAt: number;
}
```

- [ ] **Step 2: Create src/rules/interface.ts**

```ts
import type { Transaction } from "@mysten/sui/transactions";
import type { WatcherSignal, RuleConfig } from "../types.js";

export interface RuleHandler {
  readonly name: string;
  readonly description: string;
  readonly eventType?: string;
  readonly scheduleType?: "inventory" | "deadline" | "fleet";
  enabled: boolean;

  evaluate(signal: WatcherSignal, config: RuleConfig, now?: number): Promise<boolean>;
  buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction>;
}
```

- [ ] **Step 3: Create src/signer/interface.ts**

```ts
import type { Keypair } from "@mysten/sui/cryptography";

export interface SignerContext {
  ruleHandler: string;
  productionLineId?: string;
}

export interface SignerInfo {
  address: string;
  label: string;
}

export interface SignerProvider {
  getSigner(context?: SignerContext): Promise<Keypair>;
  listSigners(): Promise<SignerInfo[]>;
}
```

- [ ] **Step 4: Typecheck**

Run: `cd watcher && npx tsc --noEmit`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add watcher/src/types.ts watcher/src/rules/interface.ts watcher/src/signer/interface.ts
git commit -m "feat(watcher): add shared types and interfaces"
```

---

### Task 3: SQLite DB Layer

**Files:**
- Create: `src/db/migrations.ts`
- Create: `src/db/sqlite.ts`
- Create: `tests/db/sqlite.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/db/sqlite.test.ts
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
      // Same object, two different deadline types
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/db/sqlite.test.ts`
Expected: FAIL — modules not found

- [ ] **Step 3: Create src/db/migrations.ts**

```ts
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
```

- [ ] **Step 4: Create src/db/sqlite.ts**

```ts
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/db/sqlite.test.ts`
Expected: ALL PASS (6 tests)

- [ ] **Step 6: Commit**

```bash
git add watcher/src/db/ watcher/tests/db/
git commit -m "feat(watcher): add SQLite DB layer with migrations"
```

---

### Task 4: Config Loader & Validation

**Files:**
- Create: `src/config.ts`
- Create: `tests/config.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/config.test.ts
import { describe, it, expect } from "vitest";
import { parseConfig, validateConfig } from "../src/config.js";

const VALID_YAML = `
network: testnet
package_ids:
  industrial_core: "0xCORE"
  work_order: "0xWO"
  marketplace: "0xMKT"
signer:
  type: single
  keypath: ~/.sui/sui.keystore
watch:
  poll_interval_ms: 5000
  production_line_ids: ["0xLINE1"]
  work_order_board_id: "0xBOARD"
  marketplace_id: "0xMARKET"
  item_type_ids: [1, 2, 3]          # u32 Bag keys (1=ammo_casing, 2=refined_ore, 3=fuel_cell)
gas:
  pool_size: 20
  min_balance_warn: 100000000
  min_coin_balance: 5000000
  auto_replenish: true
rules:
  trigger_evaluator:
    enabled: true
    production_line_ids: ["0xLINE1"]
    trigger_rule_ids: ["0xTRIGGER_RULE1"]  # on-chain TriggerRule object IDs
  auto_restock:
    enabled: true
    threshold: 10
    production_line_ids: ["0xLINE2"]
    recipe_id: "0xRECIPE1"          # Recipe object ID for restock production
    blueprint_id: "0xBLUEPRINT1"    # BlueprintOriginal object ID
  output_withdrawer:
    enabled: true
  order_acceptor:
    enabled: true
    max_escrow: 5000000000
    recipe_ids: []
  order_completer:
    enabled: true
  auto_complete:
    enabled: true
  expired_cleaner:
    enabled: true
  lease_forfeiter:
    enabled: false
  fleet_damage:
    enabled: true
    mock: true
    interval_ms: 30000
  production_completer:
    enabled: true
  delivery_handler:
    enabled: true
    auto_deliver: true
`;

describe("Config", () => {
  it("parses valid YAML", () => {
    const config = parseConfig(VALID_YAML);
    expect(config.network).toBe("testnet");
    expect(config.package_ids.industrial_core).toBe("0xCORE");
    expect(config.gas.pool_size).toBe(20);
  });

  it("validates config succeeds for valid input", () => {
    const config = parseConfig(VALID_YAML);
    expect(() => validateConfig(config)).not.toThrow();
  });

  it("rejects overlapping production_line_ids between trigger_evaluator and auto_restock", () => {
    const yaml = VALID_YAML.replace(
      'production_line_ids: ["0xLINE2"]',
      'production_line_ids: ["0xLINE1"]',
    );
    const config = parseConfig(yaml);
    expect(() => validateConfig(config)).toThrow(/mutually exclusive/);
  });

  it("rejects missing package_ids", () => {
    const yaml = VALID_YAML.replace("industrial_core", "");
    const config = parseConfig(yaml);
    expect(() => validateConfig(config)).toThrow();
  });

  it("rejects invalid network", () => {
    const yaml = VALID_YAML.replace("testnet", "foonet");
    const config = parseConfig(yaml);
    expect(() => validateConfig(config)).toThrow(/network/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/config.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/config.ts**

```ts
import { readFileSync } from "node:fs";
import { parse as parseYaml } from "yaml";
import type { WatcherConfig } from "./types.js";

export function parseConfig(yamlStr: string): WatcherConfig {
  return parseYaml(yamlStr) as WatcherConfig;
}

export function loadConfig(filePath: string): WatcherConfig {
  const raw = readFileSync(filePath, "utf-8");
  const config = parseConfig(raw);
  validateConfig(config);
  return config;
}

export function validateConfig(config: WatcherConfig): void {
  // Network
  if (!["devnet", "testnet", "mainnet"].includes(config.network)) {
    throw new Error(`Invalid network: ${config.network}`);
  }

  // Package IDs
  const { package_ids } = config;
  if (
    !package_ids?.industrial_core ||
    !package_ids?.work_order ||
    !package_ids?.marketplace
  ) {
    throw new Error(
      "Missing required package_ids (industrial_core, work_order, marketplace)",
    );
  }

  // Watch
  if (!config.watch?.production_line_ids?.length) {
    throw new Error("watch.production_line_ids must have at least one entry");
  }
  if (!config.watch?.work_order_board_id) {
    throw new Error("watch.work_order_board_id is required");
  }

  // Gas
  if (config.gas?.pool_size < 1 || config.gas?.pool_size > 100) {
    throw new Error("gas.pool_size must be between 1 and 100");
  }

  // Mutual exclusivity: trigger_evaluator vs auto_restock
  const triggerLines = new Set(
    (config.rules?.trigger_evaluator as any)?.production_line_ids ?? [],
  );
  const restockLines = new Set(
    (config.rules?.auto_restock as any)?.production_line_ids ?? [],
  );
  for (const lineId of triggerLines) {
    if (restockLines.has(lineId)) {
      throw new Error(
        `Production line ${lineId} in both trigger_evaluator and auto_restock — mutually exclusive`,
      );
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/config.test.ts`
Expected: ALL PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/config.ts watcher/tests/config.test.ts
git commit -m "feat(watcher): add YAML config loader with validation"
```

---

### Task 5: SingleKeypairProvider

**Files:**
- Create: `src/signer/single.ts`
- Create: `tests/signer/single.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/signer/single.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { SingleKeypairProvider } from "../../src/signer/single.js";

// SUI keystore: JSON array of base64 strings
// first byte = scheme flag (0x00 = Ed25519), then 32-byte secret key
const MOCK_KEYSTORE = JSON.stringify([
  "ANgGe3kmT3tFCr6lRzIYuEHXGHsJJF7nvPqXkxW/yfJx",
]);

describe("SingleKeypairProvider", () => {
  let provider: SingleKeypairProvider;

  beforeEach(() => {
    provider = SingleKeypairProvider.fromKeystoreContent(MOCK_KEYSTORE);
  });

  it("returns a keypair from getSigner", async () => {
    const kp = await provider.getSigner();
    expect(kp).toBeDefined();
    expect(kp.getPublicKey()).toBeDefined();
  });

  it("returns consistent address", async () => {
    const kp1 = await provider.getSigner();
    const kp2 = await provider.getSigner({ ruleHandler: "test" });
    expect(kp1.getPublicKey().toSuiAddress()).toBe(
      kp2.getPublicKey().toSuiAddress(),
    );
  });

  it("listSigners returns one entry", async () => {
    const signers = await provider.listSigners();
    expect(signers).toHaveLength(1);
    expect(signers[0].label).toBe("default");
    expect(signers[0].address).toMatch(/^0x/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/signer/single.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/signer/single.ts**

```ts
import { readFileSync } from "node:fs";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import type { Keypair } from "@mysten/sui/cryptography";
import type { SignerProvider, SignerContext, SignerInfo } from "./interface.js";

export class SingleKeypairProvider implements SignerProvider {
  private keypair: Ed25519Keypair;

  private constructor(keypair: Ed25519Keypair) {
    this.keypair = keypair;
  }

  static fromKeystoreFile(path: string): SingleKeypairProvider {
    const content = readFileSync(path, "utf-8");
    return SingleKeypairProvider.fromKeystoreContent(content);
  }

  static fromKeystoreContent(content: string): SingleKeypairProvider {
    const keys: string[] = JSON.parse(content);
    if (keys.length === 0) throw new Error("Keystore is empty");

    // SUI keystore format: base64(scheme_flag + secret_key_bytes)
    try {
      const { schema, secretKey } = decodeSuiPrivateKey(keys[0]);
      if (schema === "ED25519") {
        return new SingleKeypairProvider(
          Ed25519Keypair.fromSecretKey(secretKey),
        );
      }
    } catch {
      // Fallback: raw decode for older keystore format
    }

    const raw = Buffer.from(keys[0], "base64");
    const scheme = raw[0]; // 0x00 = Ed25519
    if (scheme !== 0x00)
      throw new Error(`Unsupported key scheme: ${scheme}`);
    return new SingleKeypairProvider(
      Ed25519Keypair.fromSecretKey(raw.subarray(1)),
    );
  }

  async getSigner(_context?: SignerContext): Promise<Keypair> {
    return this.keypair;
  }

  async listSigners(): Promise<SignerInfo[]> {
    return [
      {
        address: this.keypair.getPublicKey().toSuiAddress(),
        label: "default",
      },
    ];
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/signer/single.test.ts`
Expected: ALL PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/signer/ watcher/tests/signer/
git commit -m "feat(watcher): add SingleKeypairProvider for SUI keystore"
```

---

### Task 6: Gas Pool

**Files:**
- Create: `src/executor/gas-pool.ts`
- Create: `tests/executor/gas-pool.test.ts`
- Create: `tests/helpers/mock-sui-client.ts`

- [ ] **Step 1: Create mock SUI client helper**

```ts
// tests/helpers/mock-sui-client.ts
import { vi } from "vitest";
import type { SuiClient } from "@mysten/sui/client";

export function createMockSuiClient(
  overrides: Partial<SuiClient> = {},
): SuiClient {
  return {
    getCoins: vi.fn(),
    getObject: vi.fn(),
    getDynamicFieldObject: vi.fn(),
    queryEvents: vi.fn(),
    signAndExecuteTransaction: vi.fn(),
    waitForTransaction: vi.fn(),
    ...overrides,
  } as unknown as SuiClient;
}
```

- [ ] **Step 2: Write the failing test**

```ts
// tests/executor/gas-pool.test.ts
import { describe, it, expect, vi } from "vitest";
import { GasPool } from "../../src/executor/gas-pool.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";

describe("GasPool", () => {
  it("initializes from existing coins", async () => {
    const client = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0x1", version: "1", digest: "d1", balance: "50000000" },
          { coinObjectId: "0x2", version: "2", digest: "d2", balance: "50000000" },
        ],
        hasNextPage: false,
      }),
    });
    const pool = new GasPool(client, "0xowner", {
      poolSize: 2,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await pool.initialize();
    expect(pool.size()).toBe(2);
  });

  it("acquires and releases coins round-robin", async () => {
    const client = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0xA", version: "1", digest: "dA", balance: "50000000" },
          { coinObjectId: "0xB", version: "2", digest: "dB", balance: "50000000" },
        ],
        hasNextPage: false,
      }),
    });
    const pool = new GasPool(client, "0xowner", {
      poolSize: 2,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await pool.initialize();

    const coin1 = pool.acquire();
    expect(coin1?.objectId).toBe("0xA");
    const coin2 = pool.acquire();
    expect(coin2?.objectId).toBe("0xB");
    // All acquired
    expect(pool.acquire()).toBeNull();
    // Release first
    pool.release("0xA");
    const coin4 = pool.acquire();
    expect(coin4?.objectId).toBe("0xA");
  });

  it("updates coin ref after TX", async () => {
    const client = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0xA", version: "1", digest: "d1", balance: "50000000" },
        ],
        hasNextPage: false,
      }),
    });
    const pool = new GasPool(client, "0xowner", {
      poolSize: 1,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await pool.initialize();

    pool.updateCoinRef("0xA", { version: "5", digest: "d5", balance: 45000000 });
    const coin = pool.acquire();
    expect(coin?.version).toBe("5");
    expect(coin?.digest).toBe("d5");
    expect(coin?.balance).toBe(45000000);
  });

  it("warns when total balance is low", async () => {
    const client = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0x1", version: "1", digest: "d1", balance: "1000" },
        ],
        hasNextPage: false,
      }),
    });
    const pool = new GasPool(client, "0xowner", {
      poolSize: 1,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await pool.initialize();
    expect(pool.isLowBalance()).toBe(true);
    expect(pool.isCriticalBalance()).toBe(true);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/executor/gas-pool.test.ts`
Expected: FAIL

- [ ] **Step 4: Implement src/executor/gas-pool.ts**

```ts
import type { SuiClient } from "@mysten/sui/client";
import type { GasCoinEntry } from "../types.js";

export interface GasPoolConfig {
  poolSize: number;
  minCoinBalance: number;
  minBalanceWarn: number;
}

export class GasPool {
  private coins: GasCoinEntry[] = [];
  private acquired = new Set<string>();
  private nextIndex = 0;

  constructor(
    private client: SuiClient,
    private ownerAddress: string,
    private config: GasPoolConfig,
  ) {}

  async initialize(): Promise<void> {
    const result = await this.client.getCoins({
      owner: this.ownerAddress,
      coinType: "0x2::sui::SUI",
    });

    this.coins = result.data.map((c) => ({
      objectId: c.coinObjectId,
      version: c.version,
      digest: c.digest,
      balance: Number(c.balance),
    }));

    // TODO: If fewer coins than poolSize, split largest coin
    // For hackathon, assume pre-split coins exist
  }

  size(): number {
    return this.coins.length;
  }

  acquire(): GasCoinEntry | null {
    const available = this.coins.filter(
      (c) => !this.acquired.has(c.objectId),
    );
    if (available.length === 0) return null;
    const coin = available[this.nextIndex % available.length];
    this.nextIndex++;
    this.acquired.add(coin.objectId);
    return coin;
  }

  release(objectId: string): void {
    this.acquired.delete(objectId);
  }

  updateCoinRef(
    objectId: string,
    update: { version: string; digest: string; balance: number },
  ): void {
    const coin = this.coins.find((c) => c.objectId === objectId);
    if (coin) {
      coin.version = update.version;
      coin.digest = update.digest;
      coin.balance = update.balance;
    }
  }

  totalBalance(): number {
    return this.coins.reduce((sum, c) => sum + c.balance, 0);
  }

  isLowBalance(): boolean {
    return this.totalBalance() < this.config.minBalanceWarn;
  }

  isCriticalBalance(): boolean {
    return this.totalBalance() < this.config.minBalanceWarn / 2;
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/executor/gas-pool.test.ts`
Expected: ALL PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add watcher/src/executor/gas-pool.ts watcher/tests/executor/ watcher/tests/helpers/
git commit -m "feat(watcher): add GasPool with round-robin acquisition"
```

---

### Task 7: TX Executor

**Files:**
- Create: `src/executor/tx-executor.ts`
- Create: `tests/executor/tx-executor.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/executor/tx-executor.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import { TxExecutor } from "../../src/executor/tx-executor.js";
import { GasPool } from "../../src/executor/gas-pool.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";
import { createDb } from "../../src/db/sqlite.js";
import type { SignerProvider } from "../../src/signer/interface.js";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

function createMockSigner(): SignerProvider {
  const kp = new Ed25519Keypair();
  return {
    getSigner: vi.fn().mockResolvedValue(kp),
    listSigners: vi.fn().mockResolvedValue([
      { address: kp.getPublicKey().toSuiAddress(), label: "test" },
    ]),
  };
}

describe("TxExecutor", () => {
  let db: Database.Database;
  let executor: TxExecutor;
  let mockClient: ReturnType<typeof createMockSuiClient>;
  let gasPool: GasPool;

  beforeEach(async () => {
    db = createDb(":memory:");
    mockClient = createMockSuiClient({
      getCoins: vi.fn().mockResolvedValue({
        data: [
          { coinObjectId: "0xGAS", version: "1", digest: "d1", balance: "50000000" },
        ],
        hasNextPage: false,
      }),
      signAndExecuteTransaction: vi.fn().mockResolvedValue({
        digest: "0xTX_DIGEST",
        effects: {
          status: { status: "success" },
          gasUsed: {
            computationCost: "1000",
            storageCost: "500",
            storageRebate: "200",
          },
          mutated: [
            {
              reference: { objectId: "0xGAS", version: "2", digest: "d2" },
            },
          ],
        },
      }),
    });
    gasPool = new GasPool(mockClient, "0xowner", {
      poolSize: 1,
      minCoinBalance: 5000000,
      minBalanceWarn: 100000000,
    });
    await gasPool.initialize();
    executor = new TxExecutor(mockClient, gasPool, createMockSigner(), db);
  });

  afterEach(() => db.close());

  it("executes a transaction successfully", async () => {
    const tx = new Transaction();
    const result = await executor.execute("test_rule", tx);
    expect(result.success).toBe(true);
    expect(result.digest).toBe("0xTX_DIGEST");
  });

  it("logs transaction to SQLite", async () => {
    const tx = new Transaction();
    await executor.execute("test_rule", tx);
    const logs = db
      .prepare("SELECT * FROM tx_log WHERE rule_name = ?")
      .all("test_rule");
    expect(logs).toHaveLength(1);
  });

  it("releases gas coin back to pool after execution", async () => {
    const tx = new Transaction();
    await executor.execute("test_rule", tx);
    const coin = gasPool.acquire();
    expect(coin).not.toBeNull();
  });

  it("returns failure when no gas coins available", async () => {
    gasPool.acquire(); // exhaust
    const tx = new Transaction();
    const result = await executor.execute("test_rule", tx);
    expect(result.success).toBe(false);
    expect(result.error).toMatch(/no gas coin/i);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/executor/tx-executor.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/executor/tx-executor.ts**

```ts
import type {
  SuiClient,
  SuiTransactionBlockResponse,
} from "@mysten/sui/client";
import type { Transaction } from "@mysten/sui/transactions";
import type Database from "better-sqlite3";
import type { GasPool } from "./gas-pool.js";
import type { SignerProvider } from "../signer/interface.js";
import { insertTxLog } from "../db/sqlite.js";

export interface TxResult {
  success: boolean;
  digest: string | null;
  error: string | null;
  gasUsed: number | null;
}

const MAX_RETRIES = 3;
const BACKOFF_BASE_MS = 1000;

export class TxExecutor {
  constructor(
    private client: SuiClient,
    private gasPool: GasPool,
    private signerProvider: SignerProvider,
    private db: Database.Database,
  ) {}

  async execute(
    ruleName: string,
    tx: Transaction,
    signalData?: string,
  ): Promise<TxResult> {
    const gasCoin = this.gasPool.acquire();
    if (!gasCoin) {
      const result: TxResult = {
        success: false,
        digest: null,
        error: "No gas coin available",
        gasUsed: null,
      };
      insertTxLog(this.db, {
        ruleName,
        txDigest: null,
        status: "failed",
        error: result.error,
        signalData: signalData ?? null,
        gasCoinId: null,
        gasUsed: null,
        createdAt: Date.now(),
      });
      return result;
    }

    try {
      const signer = await this.signerProvider.getSigner({
        ruleHandler: ruleName,
      });
      tx.setGasPayment([
        {
          objectId: gasCoin.objectId,
          version: gasCoin.version,
          digest: gasCoin.digest,
        },
      ]);

      let lastError: string | null = null;
      for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
        try {
          const response = await this.client.signAndExecuteTransaction({
            signer,
            transaction: tx,
            options: { showEffects: true },
          });

          const gasUsed = this.extractGasUsed(response);
          this.updateGasCoinFromEffects(gasCoin.objectId, response, gasCoin.balance, gasUsed);

          const success =
            response.effects?.status?.status === "success";
          const result: TxResult = {
            success,
            digest: response.digest,
            error: success
              ? null
              : (response.effects?.status?.error ?? "Unknown error"),
            gasUsed,
          };

          insertTxLog(this.db, {
            ruleName,
            txDigest: response.digest,
            status: success ? "success" : "failed",
            error: result.error,
            signalData: signalData ?? null,
            gasCoinId: gasCoin.objectId,
            gasUsed,
            createdAt: Date.now(),
          });

          return result;
        } catch (err) {
          lastError =
            err instanceof Error ? err.message : String(err);
          if (attempt < MAX_RETRIES) {
            await this.sleep(
              BACKOFF_BASE_MS * Math.pow(2, attempt),
            );
          }
        }
      }

      // All retries exhausted
      const result: TxResult = {
        success: false,
        digest: null,
        error: lastError,
        gasUsed: null,
      };
      insertTxLog(this.db, {
        ruleName,
        txDigest: null,
        status: "failed",
        error: lastError,
        signalData: signalData ?? null,
        gasCoinId: gasCoin.objectId,
        gasUsed: null,
        createdAt: Date.now(),
      });
      return result;
    } finally {
      this.gasPool.release(gasCoin.objectId);
    }
  }

  private extractGasUsed(
    response: SuiTransactionBlockResponse,
  ): number | null {
    const g = response.effects?.gasUsed;
    if (!g) return null;
    return (
      Number(g.computationCost) +
      Number(g.storageCost) -
      Number(g.storageRebate)
    );
  }

  private updateGasCoinFromEffects(
    gasCoinId: string,
    response: SuiTransactionBlockResponse,
    previousBalance: number,
    gasUsed: number | null,
  ): void {
    const mutated = response.effects?.mutated;
    if (!mutated) return;
    for (const obj of mutated) {
      const ref = obj.reference;
      if (ref && ref.objectId === gasCoinId) {
        // Approximate balance: previous - gasUsed (actual balance not in effects.mutated)
        const estimatedBalance = previousBalance - (gasUsed ?? 0);
        this.gasPool.updateCoinRef(gasCoinId, {
          version: ref.version,
          digest: ref.digest,
          balance: Math.max(0, estimatedBalance),
        });
        return;
      }
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/executor/tx-executor.test.ts`
Expected: ALL PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/executor/tx-executor.ts watcher/tests/executor/tx-executor.test.ts
git commit -m "feat(watcher): add TxExecutor with retry + gas management"
```

---

### Task 8: PTB Builder Helpers

**Files:**
- Create: `src/executor/ptb-builder.ts`

Pure TX construction wrappers — tested via rule handler tests.

- [ ] **Step 1: Implement src/executor/ptb-builder.ts**

```ts
import { Transaction } from "@mysten/sui/transactions";

// ─── industrial_core::production_line ───────────

export function completeProduction(
  tx: Transaction,
  pkg: string,
  lineId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::production_line::complete_production`,
    arguments: [tx.object(lineId), tx.object(clockId)],
  });
  return tx;
}

export function withdrawOutput(
  tx: Transaction,
  pkg: string,
  lineId: string,
  itemTypeId: number,
  quantity: number,
): Transaction {
  tx.moveCall({
    target: `${pkg}::production_line::withdraw_output`,
    arguments: [
      tx.object(lineId),
      tx.pure.u32(itemTypeId),
      tx.pure.u64(quantity),
    ],
  });
  return tx;
}

export function startProduction(
  tx: Transaction,
  pkg: string,
  lineId: string,
  recipeId: string,
  blueprintId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::production_line::start_production`,
    arguments: [
      tx.object(lineId),
      tx.object(recipeId),
      tx.object(blueprintId),
      tx.object(clockId),
    ],
  });
  return tx;
}

// ─── industrial_core::trigger_engine ────────────

export function executeTrigger(
  tx: Transaction,
  pkg: string,
  ruleId: string,
  lineId: string,
  recipeId: string,
  blueprintId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::trigger_engine::execute_trigger`,
    arguments: [
      tx.object(ruleId),
      tx.object(lineId),
      tx.object(recipeId),
      tx.object(blueprintId),
      tx.object(clockId),
    ],
  });
  return tx;
}

// ─── work_order ─────────────────────────────────

export function acceptWorkOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::accept_work_order`,
    arguments: [tx.object(orderId)],
  });
  return tx;
}

export function deliverWorkOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
  itemTypeId: number,
  quantity: number,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::deliver_work_order`,
    arguments: [
      tx.object(orderId),
      tx.pure.u32(itemTypeId),
      tx.pure.u64(quantity),
      tx.object(clockId),
    ],
  });
  return tx;
}

export function completeWorkOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
  boardId: string,
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::complete_work_order`,
    arguments: [tx.object(orderId), tx.object(boardId)],
  });
  return tx;
}

export function autoCompleteWorkOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
  boardId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::auto_complete_work_order`,
    arguments: [
      tx.object(orderId),
      tx.object(boardId),
      tx.object(clockId),
    ],
  });
  return tx;
}

export function cancelExpiredOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
  boardId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::cancel_expired_order`,
    arguments: [
      tx.object(orderId),
      tx.object(boardId),
      tx.object(clockId),
    ],
  });
  return tx;
}

// ─── work_order::fleet_integration ──────────────

export function createOrderFromDamageReport(
  tx: Transaction,
  pkg: string,
  boardId: string,
  description: string,
  recipeId: string,
  quantity: number,
  paymentCoinId: string,
  deadline: number,
  sourceEvent: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::fleet_integration::create_order_from_damage_report`,
    arguments: [
      tx.object(boardId),
      tx.pure.string(description),
      tx.pure.id(recipeId),
      tx.pure.u64(quantity),
      tx.object(paymentCoinId),
      tx.pure.u64(deadline),
      tx.pure.string(sourceEvent),
      tx.object(clockId),
    ],
  });
  return tx;
}

// ─── marketplace::lease ─────────────────────────

export function forfeitLease(
  tx: Transaction,
  pkg: string,
  leaseId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::lease::forfeit_lease`,
    arguments: [tx.object(leaseId), tx.object(clockId)],
  });
  return tx;
}
```

- [ ] **Step 2: Typecheck**

Run: `cd watcher && npx tsc --noEmit`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add watcher/src/executor/ptb-builder.ts
git commit -m "feat(watcher): add PTB builder with moveCall wrappers"
```

---

### Task 9: Event Poller

**Files:**
- Create: `src/poller/event-poller.ts`
- Create: `tests/poller/event-poller.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/poller/event-poller.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import { EventPoller } from "../../src/poller/event-poller.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";
import { createDb } from "../../src/db/sqlite.js";

describe("EventPoller", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = createDb(":memory:");
  });
  afterEach(() => db.close());

  it("fetches events and returns them", async () => {
    const mockEvents = [
      {
        id: { txDigest: "0xA", eventSeq: "0" },
        type: "0xPKG::production_line::ProductionCompletedEvent",
        parsedJson: { output_quantity: "10" },
        packageId: "0xPKG",
        transactionModule: "production_line",
        sender: "0x",
        bcs: "",
        timestampMs: "0",
      },
    ];
    const client = createMockSuiClient({
      queryEvents: vi.fn().mockResolvedValue({
        data: mockEvents,
        hasNextPage: false,
        nextCursor: { txDigest: "0xA", eventSeq: "0" },
      }),
    });
    const poller = new EventPoller(client, db, ["0xPKG"]);
    const events = await poller.poll();
    expect(events).toHaveLength(1);
    expect(events[0].type).toContain("ProductionCompletedEvent");
  });

  it("persists cursor across polls", async () => {
    const client = createMockSuiClient({
      queryEvents: vi
        .fn()
        .mockResolvedValueOnce({
          data: [
            {
              id: { txDigest: "0xA", eventSeq: "0" },
              type: "t",
              parsedJson: {},
              packageId: "0xPKG",
              transactionModule: "m",
              sender: "0x",
              bcs: "",
              timestampMs: "0",
            },
          ],
          hasNextPage: false,
          nextCursor: { txDigest: "0xA", eventSeq: "0" },
        })
        .mockResolvedValueOnce({
          data: [],
          hasNextPage: false,
          nextCursor: null,
        }),
    });
    const poller = new EventPoller(client, db, ["0xPKG"]);
    await poller.poll();
    await poller.poll();
    const secondCall = (client.queryEvents as any).mock.calls[1][0];
    expect(secondCall.cursor).toEqual({
      txDigest: "0xA",
      eventSeq: "0",
    });
  });

  it("resumes from persisted cursor on new instance", async () => {
    const client = createMockSuiClient({
      queryEvents: vi.fn().mockResolvedValue({
        data: [],
        hasNextPage: false,
        nextCursor: null,
      }),
    });
    db.prepare(
      "INSERT INTO cursors (event_type, cursor_id, updated_at) VALUES (?, ?, ?)",
    ).run(
      "events:0xPKG",
      JSON.stringify({ txDigest: "0xPREV", eventSeq: "5" }),
      Date.now(),
    );
    const poller = new EventPoller(client, db, ["0xPKG"]);
    await poller.poll();
    const call = (client.queryEvents as any).mock.calls[0][0];
    expect(call.cursor).toEqual({ txDigest: "0xPREV", eventSeq: "5" });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/poller/event-poller.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/poller/event-poller.ts**

```ts
import type { SuiClient, SuiEvent, EventId } from "@mysten/sui/client";
import type Database from "better-sqlite3";
import { getCursor, setCursor } from "../db/sqlite.js";

/**
 * Polls events from multiple packages. Each package gets its own cursor
 * stored in SQLite as `events:{packageId}`. Uses `Sender` filter per package
 * since `MoveModule` with empty module is unreliable.
 *
 * Alternative approach: one poller per package — simpler but more RPC calls.
 * We use one poller with multiple queries for fewer instantiations.
 */
export class EventPoller {
  private cursors = new Map<string, EventId>();
  private initialized = false;

  constructor(
    private client: SuiClient,
    private db: Database.Database,
    private packageIds: string[],
  ) {}

  private loadCursors(): void {
    if (this.initialized) return;
    for (const pkgId of this.packageIds) {
      const raw = getCursor(this.db, `events:${pkgId}`);
      if (raw) {
        this.cursors.set(pkgId, JSON.parse(raw));
      }
    }
    this.initialized = true;
  }

  async poll(): Promise<SuiEvent[]> {
    this.loadCursors();
    const allEvents: SuiEvent[] = [];

    for (const pkgId of this.packageIds) {
      const cursor = this.cursors.get(pkgId);
      const result = await this.client.queryEvents({
        query: { MoveEventModule: { package: pkgId, module: "*" } },
        cursor: cursor ?? undefined,
        order: "ascending",
      });

      allEvents.push(...result.data);

      if (result.data.length > 0 && result.nextCursor) {
        this.cursors.set(pkgId, result.nextCursor);
        setCursor(
          this.db,
          `events:${pkgId}`,
          JSON.stringify(result.nextCursor),
        );
      }
    }

    return allEvents;
  }
}
```

> **Note:** At implementation time, verify which `queryEvents` filter works for your SUI SDK version. If `MoveEventModule` with `module: "*"` fails, fall back to one `queryEvents` call per known module (e.g., `production_line`, `work_order`, `marketplace`, `lease`, `trigger_engine`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/poller/event-poller.test.ts`
Expected: ALL PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/poller/event-poller.ts watcher/tests/poller/event-poller.test.ts
git commit -m "feat(watcher): add EventPoller with cursor persistence"
```

---

### Task 10: Inventory Monitor

**Files:**
- Create: `src/poller/inventory-monitor.ts`
- Create: `tests/poller/inventory-monitor.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/poller/inventory-monitor.test.ts
import { describe, it, expect, vi } from "vitest";
import { InventoryMonitor } from "../../src/poller/inventory-monitor.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";

describe("InventoryMonitor", () => {
  it("polls production line and returns inventory snapshot", async () => {
    const client = createMockSuiClient({
      getObject: vi.fn().mockResolvedValue({
        data: {
          content: {
            fields: {
              status: 0,
              current_job_end: "0",
              fuel_reserve: "500",
            },
          },
        },
      }),
      getDynamicFieldObject: vi.fn().mockResolvedValue({
        data: {
          content: { fields: { value: "3" } },
        },
      }),
    });

    const monitor = new InventoryMonitor(client, ["0xLINE1"], [1, 2]);
    const snapshots = await monitor.poll();

    expect(snapshots).toHaveLength(1);
    expect(snapshots[0].productionLineId).toBe("0xLINE1");
    expect(snapshots[0].items.get(1)).toBe(3);
  });

  it("reads production line status for running jobs", async () => {
    const client = createMockSuiClient({
      getObject: vi.fn().mockResolvedValue({
        data: {
          content: {
            fields: {
              status: 1,
              current_job_end: "1711000000000",
              fuel_reserve: "100",
            },
          },
        },
      }),
      getDynamicFieldObject: vi.fn().mockResolvedValue({
        data: { content: { fields: { value: "50" } } },
      }),
    });

    const monitor = new InventoryMonitor(client, ["0xLINE1"], [1]);
    const snapshots = await monitor.poll();

    expect(snapshots[0].status).toBe(1);
    expect(snapshots[0].currentJobEnd).toBe(1711000000000);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/poller/inventory-monitor.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/poller/inventory-monitor.ts**

```ts
import type { SuiClient } from "@mysten/sui/client";
import type { InventorySnapshot } from "../types.js";

export class InventoryMonitor {
  constructor(
    private client: SuiClient,
    private productionLineIds: string[],
    private itemTypeIds: number[],
  ) {}

  async poll(): Promise<InventorySnapshot[]> {
    const snapshots: InventorySnapshot[] = [];
    for (const lineId of this.productionLineIds) {
      const snapshot = await this.pollLine(lineId);
      if (snapshot) snapshots.push(snapshot);
    }
    return snapshots;
  }

  private async pollLine(
    lineId: string,
  ): Promise<InventorySnapshot | null> {
    const lineObj = await this.client.getObject({
      id: lineId,
      options: { showContent: true },
    });

    const fields = (lineObj.data?.content as any)?.fields;
    if (!fields) return null;

    const items = new Map<number, number>();

    for (const itemTypeId of this.itemTypeIds) {
      try {
        const dynField = await this.client.getDynamicFieldObject({
          parentId: lineId,
          name: { type: "u32", value: itemTypeId },
        });
        const quantity = Number(
          (dynField.data?.content as any)?.fields?.value ?? 0,
        );
        items.set(itemTypeId, quantity);
      } catch {
        items.set(itemTypeId, 0);
      }
    }

    return {
      productionLineId: lineId,
      items,
      status: Number(fields.status),
      currentJobEnd: Number(fields.current_job_end ?? 0),
      fuelReserve: Number(fields.fuel_reserve ?? 0),
    };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/poller/inventory-monitor.test.ts`
Expected: ALL PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/poller/inventory-monitor.ts watcher/tests/poller/inventory-monitor.test.ts
git commit -m "feat(watcher): add InventoryMonitor with getDynamicFieldObject"
```

---

### Task 11: Deadline Scheduler

**Files:**
- Create: `src/poller/deadline-scheduler.ts`
- Create: `tests/poller/deadline-scheduler.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/poller/deadline-scheduler.test.ts
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
    // auto_complete = acceptance_time + 72h
    expect((rows[0] as any).deadline_at).toBe(
      1710000000000 + 72 * 60 * 60 * 1000,
    );
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/poller/deadline-scheduler.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/poller/deadline-scheduler.ts**

```ts
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/poller/deadline-scheduler.test.ts`
Expected: ALL PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/poller/deadline-scheduler.ts watcher/tests/poller/deadline-scheduler.test.ts
git commit -m "feat(watcher): add DeadlineScheduler with event extraction"
```

---

### Task 12: Fleet Listener (Mock)

**Files:**
- Create: `src/poller/fleet-listener.ts`
- Create: `tests/poller/fleet-listener.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/poller/fleet-listener.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { FleetListener } from "../../src/poller/fleet-listener.js";

describe("FleetListener", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("generates mock damage reports on interval", () => {
    const reports: any[] = [];
    const listener = new FleetListener({
      mock: true,
      intervalMs: 5000,
      recipeIds: ["0xREC1", "0xREC2"],
      onReport: (r) => reports.push(r),
    });
    listener.start();
    vi.advanceTimersByTime(5000);
    expect(reports).toHaveLength(1);
    expect(reports[0].recipeId).toMatch(/^0xREC/);

    vi.advanceTimersByTime(5000);
    expect(reports).toHaveLength(2);
    listener.stop();
  });

  it("does nothing when mock is false", () => {
    const reports: any[] = [];
    const listener = new FleetListener({
      mock: false,
      intervalMs: 5000,
      recipeIds: ["0xREC1"],
      onReport: (r) => reports.push(r),
    });
    listener.start();
    vi.advanceTimersByTime(10000);
    expect(reports).toHaveLength(0);
    listener.stop();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/poller/fleet-listener.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/poller/fleet-listener.ts**

```ts
import type { MockDamageReport } from "../types.js";

export interface FleetListenerConfig {
  mock: boolean;
  intervalMs: number;
  recipeIds: string[];
  onReport: (report: MockDamageReport) => void;
}

export class FleetListener {
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(private config: FleetListenerConfig) {}

  start(): void {
    if (!this.config.mock) return;
    if (this.config.recipeIds.length === 0) return;

    this.timer = setInterval(() => {
      const report = this.generateReport();
      this.config.onReport(report);
    }, this.config.intervalMs);
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private generateReport(): MockDamageReport {
    const recipeId =
      this.config.recipeIds[
        Math.floor(Math.random() * this.config.recipeIds.length)
      ];
    return {
      recipeId,
      quantity: Math.floor(Math.random() * 10) + 1,
      priority: 3, // CRITICAL
      description: `Fleet damage report: ${recipeId} — automated mock`,
    };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/poller/fleet-listener.test.ts`
Expected: ALL PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/poller/fleet-listener.ts watcher/tests/poller/fleet-listener.test.ts
git commit -m "feat(watcher): add FleetListener with mock damage reports"
```

---

### Task 13: Rule Registry

**Files:**
- Create: `src/rules/registry.ts`
- Create: `tests/rules/registry.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/rules/registry.test.ts
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/rules/registry.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/rules/registry.ts**

```ts
import type { RuleHandler } from "./interface.js";

export class RuleRegistry {
  private handlers: RuleHandler[] = [];

  register(handler: RuleHandler): void {
    this.handlers.push(handler);
  }

  getByEventType(type: string): RuleHandler[] {
    return this.handlers.filter(
      (h) => h.enabled && h.eventType && type.endsWith(h.eventType),
    );
  }

  getByScheduleType(type: string): RuleHandler[] {
    return this.handlers.filter(
      (h) => h.enabled && h.scheduleType === type,
    );
  }

  listAll(): RuleHandler[] {
    return [...this.handlers];
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/rules/registry.test.ts`
Expected: ALL PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/rules/registry.ts watcher/tests/rules/registry.test.ts
git commit -m "feat(watcher): add RuleRegistry with event/schedule lookup"
```

---

### Task 14: Production Rule Handlers (4 rules)

**Files:**
- Create: `src/rules/production-completer.ts`
- Create: `src/rules/output-withdrawer.ts`
- Create: `src/rules/trigger-evaluator.ts`
- Create: `src/rules/auto-restock.ts`
- Create: corresponding test files in `tests/rules/`

- [ ] **Step 1: Write failing test for ProductionCompleter**

```ts
// tests/rules/production-completer.test.ts
import { describe, it, expect } from "vitest";
import { ProductionCompleter } from "../../src/rules/production-completer.js";
import type { WatcherSignal } from "../../src/types.js";

describe("ProductionCompleter", () => {
  const handler = new ProductionCompleter("0xCORE");

  it("evaluates true when job is done (RUNNING + jobEnd <= now)", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1",
        items: new Map(),
        status: 1,
        currentJobEnd: 1000,
        fuelReserve: 100,
      },
    };
    expect(await handler.evaluate(signal, { enabled: true }, 2000)).toBe(true);
  });

  it("evaluates false when job still running", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1",
        items: new Map(),
        status: 1,
        currentJobEnd: 5000,
        fuelReserve: 100,
      },
    };
    expect(await handler.evaluate(signal, { enabled: true }, 2000)).toBe(false);
  });

  it("evaluates false when line is IDLE", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1",
        items: new Map(),
        status: 0,
        currentJobEnd: 0,
        fuelReserve: 100,
      },
    };
    expect(await handler.evaluate(signal, { enabled: true }, 2000)).toBe(false);
  });

  it("builds complete_production PTB", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1",
        items: new Map(),
        status: 1,
        currentJobEnd: 1000,
        fuelReserve: 100,
      },
    };
    const tx = await handler.buildTx(signal, { enabled: true });
    expect(tx).toBeDefined();
  });
});
```

- [ ] **Step 2: Implement ProductionCompleter**

```ts
// src/rules/production-completer.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { completeProduction } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class ProductionCompleter implements RuleHandler {
  readonly name = "production_completer";
  readonly description = "Complete finished production jobs";
  readonly scheduleType = "inventory" as const;
  enabled = true;

  constructor(private corePackageId: string) {}

  async evaluate(
    signal: WatcherSignal,
    _config: RuleConfig,
    now?: number,
  ): Promise<boolean> {
    const inv = signal.inventoryData;
    if (!inv) return false;
    if (inv.status !== 1) return false;
    if (inv.currentJobEnd === 0) return false;
    return inv.currentJobEnd <= (now ?? Date.now());
  }

  async buildTx(
    signal: WatcherSignal,
    _config: RuleConfig,
  ): Promise<Transaction> {
    const tx = new Tx();
    completeProduction(
      tx,
      this.corePackageId,
      signal.inventoryData!.productionLineId,
    );
    return tx;
  }
}
```

- [ ] **Step 3: Run ProductionCompleter test**

Run: `cd watcher && npx vitest run tests/rules/production-completer.test.ts`
Expected: ALL PASS

- [ ] **Step 4: Write failing test for OutputWithdrawer**

```ts
// tests/rules/output-withdrawer.test.ts
import { describe, it, expect } from "vitest";
import { OutputWithdrawer } from "../../src/rules/output-withdrawer.js";
import type { WatcherSignal } from "../../src/types.js";

function makeCompletedSignal(qty: string): WatcherSignal {
  return {
    type: "event",
    eventData: {
      id: { txDigest: "0x1", eventSeq: "0" },
      type: "0xCORE::production_line::ProductionCompletedEvent",
      parsedJson: {
        production_line_id: "0xLINE1",
        output_item_type_id: 42,
        output_quantity: qty,
      },
      packageId: "0xCORE",
      transactionModule: "production_line",
      sender: "0x",
      bcs: "",
      timestampMs: "0",
    },
  };
}

describe("OutputWithdrawer", () => {
  const handler = new OutputWithdrawer("0xCORE");

  it("evaluates true on ProductionCompletedEvent with output", async () => {
    expect(
      await handler.evaluate(makeCompletedSignal("100"), { enabled: true }),
    ).toBe(true);
  });

  it("builds withdraw_output PTB", async () => {
    const tx = await handler.buildTx(makeCompletedSignal("100"), {
      enabled: true,
    });
    expect(tx).toBeDefined();
  });
});
```

- [ ] **Step 5: Implement OutputWithdrawer**

```ts
// src/rules/output-withdrawer.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { withdrawOutput } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class OutputWithdrawer implements RuleHandler {
  readonly name = "output_withdrawer";
  readonly description = "Withdraw completed production output";
  readonly eventType = "ProductionCompletedEvent";
  enabled = true;

  constructor(private corePackageId: string) {}

  async evaluate(
    signal: WatcherSignal,
    _config: RuleConfig,
  ): Promise<boolean> {
    const parsed = signal.eventData?.parsedJson as Record<string, any>;
    return !!parsed?.output_quantity && Number(parsed.output_quantity) > 0;
  }

  async buildTx(
    signal: WatcherSignal,
    _config: RuleConfig,
  ): Promise<Transaction> {
    const parsed = signal.eventData!.parsedJson as Record<string, any>;
    const tx = new Tx();
    withdrawOutput(
      tx,
      this.corePackageId,
      parsed.production_line_id,
      Number(parsed.output_item_type_id),
      Number(parsed.output_quantity),
    );
    return tx;
  }
}
```

- [ ] **Step 6: Write failing test for TriggerEvaluator**

```ts
// tests/rules/trigger-evaluator.test.ts
import { describe, it, expect } from "vitest";
import { TriggerEvaluator } from "../../src/rules/trigger-evaluator.js";
import type { WatcherSignal } from "../../src/types.js";

describe("TriggerEvaluator", () => {
  it("evaluates true for configured production lines", async () => {
    const handler = new TriggerEvaluator("0xCORE", []);
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1",
        items: new Map([[1, 5]]),
        status: 0,
        currentJobEnd: 0,
        fuelReserve: 100,
      },
    };
    expect(
      await handler.evaluate(signal, {
        enabled: true,
        production_line_ids: ["0xLINE1"],
      }),
    ).toBe(true);
  });

  it("evaluates false for unconfigured lines", async () => {
    const handler = new TriggerEvaluator("0xCORE", []);
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xOTHER",
        items: new Map(),
        status: 0,
        currentJobEnd: 0,
        fuelReserve: 100,
      },
    };
    expect(
      await handler.evaluate(signal, {
        enabled: true,
        production_line_ids: ["0xLINE1"],
      }),
    ).toBe(false);
  });
});
```

- [ ] **Step 7: Implement TriggerEvaluator**

```ts
// src/rules/trigger-evaluator.ts
import type { SuiClient } from "@mysten/sui/client";
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { executeTrigger } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

interface TriggerRuleInfo {
  ruleId: string;
  productionLineId: string;
  recipeId: string;    // fetched from on-chain TriggerRule.production_line_id → line.recipe_id
  blueprintId: string; // from config — owner must pre-assign a BPO per trigger rule
}

export class TriggerEvaluator implements RuleHandler {
  readonly name = "trigger_evaluator";
  readonly description =
    "Evaluate on-chain trigger rules and execute them";
  readonly scheduleType = "inventory" as const;
  enabled = true;

  constructor(
    private corePackageId: string,
    private triggerRules: TriggerRuleInfo[], // pre-configured from config
  ) {}

  async evaluate(
    signal: WatcherSignal,
    config: RuleConfig,
  ): Promise<boolean> {
    const inv = signal.inventoryData;
    if (!inv) return false;
    const lineIds: string[] =
      (config as any).production_line_ids ?? [];
    return lineIds.includes(inv.productionLineId);
  }

  async buildTx(
    signal: WatcherSignal,
    _config: RuleConfig,
  ): Promise<Transaction> {
    const tx = new Tx();
    const lineId = signal.inventoryData!.productionLineId;
    const matchingRules = this.triggerRules.filter(
      (r) => r.productionLineId === lineId,
    );
    for (const rule of matchingRules) {
      executeTrigger(
        tx,
        this.corePackageId,
        rule.ruleId,
        lineId,
        rule.recipeId,
        rule.blueprintId,
      );
    }
    return tx;
  }
}
```

> **Config requirement:** Each trigger rule entry in config must include `rule_id`, `production_line_id`, `recipe_id`, and `blueprint_id`. These are pre-configured object IDs known to the watcher owner.

- [ ] **Step 8: Write failing test for AutoRestock**

```ts
// tests/rules/auto-restock.test.ts
import { describe, it, expect } from "vitest";
import { AutoRestock } from "../../src/rules/auto-restock.js";
import type { WatcherSignal } from "../../src/types.js";

describe("AutoRestock", () => {
  const handler = new AutoRestock("0xCORE");

  it("evaluates true when material below threshold and IDLE", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1",
        items: new Map([[1, 3]]),
        status: 0,
        currentJobEnd: 0,
        fuelReserve: 100,
      },
    };
    expect(
      await handler.evaluate(signal, {
        enabled: true,
        threshold: 10,
        production_line_ids: ["0xLINE1"],
      }),
    ).toBe(true);
  });

  it("evaluates false when all materials above threshold", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1",
        items: new Map([[1, 50]]),
        status: 0,
        currentJobEnd: 0,
        fuelReserve: 100,
      },
    };
    expect(
      await handler.evaluate(signal, {
        enabled: true,
        threshold: 10,
        production_line_ids: ["0xLINE1"],
      }),
    ).toBe(false);
  });

  it("evaluates false when line is RUNNING", async () => {
    const signal: WatcherSignal = {
      type: "inventory",
      inventoryData: {
        productionLineId: "0xLINE1",
        items: new Map([[1, 3]]),
        status: 1,
        currentJobEnd: 5000,
        fuelReserve: 100,
      },
    };
    expect(
      await handler.evaluate(signal, {
        enabled: true,
        threshold: 10,
        production_line_ids: ["0xLINE1"],
      }),
    ).toBe(false);
  });
});
```

- [ ] **Step 9: Implement AutoRestock**

```ts
// src/rules/auto-restock.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { startProduction } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class AutoRestock implements RuleHandler {
  readonly name = "auto_restock";
  readonly description =
    "Start production when inventory drops below threshold";
  readonly scheduleType = "inventory" as const;
  enabled = true;

  constructor(private corePackageId: string) {}

  async evaluate(
    signal: WatcherSignal,
    config: RuleConfig,
  ): Promise<boolean> {
    const inv = signal.inventoryData;
    if (!inv) return false;
    if (inv.status !== 0) return false;
    const lineIds: string[] =
      (config as any).production_line_ids ?? [];
    if (!lineIds.includes(inv.productionLineId)) return false;
    const threshold = Number((config as any).threshold ?? 0);
    for (const [, qty] of inv.items) {
      if (qty < threshold) return true;
    }
    return false;
  }

  async buildTx(
    signal: WatcherSignal,
    config: RuleConfig,
  ): Promise<Transaction> {
    const tx = new Tx();
    const recipeId = (config as any).recipe_id ?? "";
    const blueprintId = (config as any).blueprint_id ?? "";
    startProduction(
      tx,
      this.corePackageId,
      signal.inventoryData!.productionLineId,
      recipeId,
      blueprintId,
    );
    return tx;
  }
}
```

- [ ] **Step 10: Run all production rule tests**

Run: `cd watcher && npx vitest run tests/rules/production-completer.test.ts tests/rules/output-withdrawer.test.ts tests/rules/trigger-evaluator.test.ts tests/rules/auto-restock.test.ts`
Expected: ALL PASS

- [ ] **Step 11: Commit**

```bash
git add watcher/src/rules/production-completer.ts watcher/src/rules/output-withdrawer.ts watcher/src/rules/trigger-evaluator.ts watcher/src/rules/auto-restock.ts watcher/tests/rules/
git commit -m "feat(watcher): add 4 production rule handlers"
```

---

### Task 15: Work Order Rule Handlers (5 rules)

**Files:**
- Create: `src/rules/order-acceptor.ts`, `order-completer.ts`, `auto-complete.ts`, `expired-cleaner.ts`, `delivery-handler.ts`
- Create: corresponding test files

- [ ] **Step 1: Write failing test for OrderAcceptor**

```ts
// tests/rules/order-acceptor.test.ts
import { describe, it, expect } from "vitest";
import { OrderAcceptor } from "../../src/rules/order-acceptor.js";
import type { WatcherSignal } from "../../src/types.js";

function makeCreatedSignal(escrow: string, recipeId: string): WatcherSignal {
  return {
    type: "event",
    eventData: {
      id: { txDigest: "0x1", eventSeq: "0" },
      type: "0xWO::work_order::WorkOrderCreated",
      parsedJson: { order_id: "0xORDER1", recipe_id: recipeId, escrow_amount: escrow },
      packageId: "0xWO", transactionModule: "work_order", sender: "0x", bcs: "", timestampMs: "0",
    },
  };
}

describe("OrderAcceptor", () => {
  const handler = new OrderAcceptor("0xWO");

  it("accepts when escrow within limit", async () => {
    expect(
      await handler.evaluate(makeCreatedSignal("1000000000", "0xREC1"), {
        enabled: true, max_escrow: 5000000000, recipe_ids: [],
      }),
    ).toBe(true);
  });

  it("rejects when escrow exceeds limit", async () => {
    expect(
      await handler.evaluate(makeCreatedSignal("9999999999", "0xREC1"), {
        enabled: true, max_escrow: 5000000000, recipe_ids: [],
      }),
    ).toBe(false);
  });

  it("rejects when recipe not in allow list", async () => {
    expect(
      await handler.evaluate(makeCreatedSignal("1000", "0xBAD"), {
        enabled: true, max_escrow: 5000000000, recipe_ids: ["0xREC1"],
      }),
    ).toBe(false);
  });
});
```

- [ ] **Step 2: Implement OrderAcceptor**

```ts
// src/rules/order-acceptor.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { acceptWorkOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class OrderAcceptor implements RuleHandler {
  readonly name = "order_acceptor";
  readonly description = "Accept matching work orders";
  readonly eventType = "WorkOrderCreated";
  enabled = true;

  constructor(private woPackageId: string) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    const parsed = signal.eventData?.parsedJson as Record<string, any>;
    if (!parsed) return false;
    const maxEscrow = Number((config as any).max_escrow ?? Infinity);
    if (Number(parsed.escrow_amount) > maxEscrow) return false;
    const allowed: string[] = (config as any).recipe_ids ?? [];
    if (allowed.length > 0 && !allowed.includes(parsed.recipe_id)) return false;
    return true;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const parsed = signal.eventData!.parsedJson as Record<string, any>;
    const tx = new Tx();
    acceptWorkOrder(tx, this.woPackageId, parsed.order_id);
    return tx;
  }
}
```

- [ ] **Step 3: Write tests + implement OrderCompleter, AutoComplete, ExpiredCleaner, DeliveryHandler**

Each follows the same pattern. Key evaluate logic:

**OrderCompleter** (`eventType: "WorkOrderDelivered"`):
- Always evaluates true (contract enforces issuer == sender)
- Builds `completeWorkOrder` PTB

**AutoComplete** (`scheduleType: "deadline"`):
- Evaluates true when `deadlineType === "auto_complete"`
- Builds `autoCompleteWorkOrder` PTB

**ExpiredCleaner** (`scheduleType: "deadline"`):
- Evaluates true when `deadlineType === "expire"`
- Builds `cancelExpiredOrder` PTB

**DeliveryHandler** (`eventType: "WorkOrderAccepted"`):
- Evaluates true when `config.auto_deliver === true`
- Builds `deliverWorkOrder` PTB

```ts
// src/rules/order-completer.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { completeWorkOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class OrderCompleter implements RuleHandler {
  readonly name = "order_completer";
  readonly description = "Complete delivered work orders (issuer)";
  readonly eventType = "WorkOrderDelivered";
  enabled = true;

  constructor(
    private woPackageId: string,
    private boardId: string,
  ) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return !!signal.eventData?.parsedJson;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const parsed = signal.eventData!.parsedJson as Record<string, any>;
    const tx = new Tx();
    completeWorkOrder(tx, this.woPackageId, parsed.order_id, this.boardId);
    return tx;
  }
}
```

```ts
// src/rules/auto-complete.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { autoCompleteWorkOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class AutoComplete implements RuleHandler {
  readonly name = "auto_complete";
  readonly description = "Auto-complete work orders after 72h (acceptor)";
  readonly scheduleType = "deadline" as const;
  enabled = true;

  constructor(private woPackageId: string, private boardId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return signal.deadlineData?.deadlineType === "auto_complete";
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    autoCompleteWorkOrder(tx, this.woPackageId, signal.deadlineData!.objectId, this.boardId);
    return tx;
  }
}
```

```ts
// src/rules/expired-cleaner.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { cancelExpiredOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class ExpiredCleaner implements RuleHandler {
  readonly name = "expired_cleaner";
  readonly description = "Cancel expired work orders (permissionless)";
  readonly scheduleType = "deadline" as const;
  enabled = true;

  constructor(private woPackageId: string, private boardId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return signal.deadlineData?.deadlineType === "expire";
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    cancelExpiredOrder(tx, this.woPackageId, signal.deadlineData!.objectId, this.boardId);
    return tx;
  }
}
```

```ts
// src/rules/delivery-handler.ts
import type { SuiClient } from "@mysten/sui/client";
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { deliverWorkOrder } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class DeliveryHandler implements RuleHandler {
  readonly name = "delivery_handler";
  readonly description = "Auto-deliver for accepted orders (acceptor)";
  readonly eventType = "WorkOrderAccepted";
  enabled = true;

  constructor(
    private woPackageId: string,
    private client: SuiClient,
  ) {}

  async evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean> {
    if (!(config as any).auto_deliver) return false;
    return !!signal.eventData?.parsedJson;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const parsed = signal.eventData!.parsedJson as Record<string, any>;
    const orderId = parsed.order_id;

    // Fetch work order on-chain to get recipe_id → resolve item_type_id and quantity
    const orderObj = await this.client.getObject({
      id: orderId,
      options: { showContent: true },
    });
    const fields = (orderObj.data?.content as any)?.fields;
    const quantityRequired = Number(fields?.quantity_required ?? 0);
    // item_type_id comes from the recipe's output — for hackathon, use 0 as placeholder
    // (the contract's deliver_work_order only tracks quantity, item_type_id is ignored)
    const itemTypeId = 0;

    const tx = new Tx();
    deliverWorkOrder(tx, this.woPackageId, orderId, itemTypeId, quantityRequired);
    return tx;
  }
}
```

- [ ] **Step 4: Run all work order rule tests**

Run: `cd watcher && npx vitest run tests/rules/order-acceptor.test.ts tests/rules/order-completer.test.ts tests/rules/auto-complete.test.ts tests/rules/expired-cleaner.test.ts tests/rules/delivery-handler.test.ts`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add watcher/src/rules/order-acceptor.ts watcher/src/rules/order-completer.ts watcher/src/rules/auto-complete.ts watcher/src/rules/expired-cleaner.ts watcher/src/rules/delivery-handler.ts watcher/tests/rules/
git commit -m "feat(watcher): add 5 work order rule handlers"
```

---

### Task 16: Remaining Rule Handlers (LeaseForfeiter + FleetDamageHandler)

**Files:**
- Create: `src/rules/lease-forfeiter.ts`, `src/rules/fleet-damage.ts`
- Create: corresponding test files

- [ ] **Step 1: Implement LeaseForfeiter**

```ts
// src/rules/lease-forfeiter.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { forfeitLease } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class LeaseForfeiter implements RuleHandler {
  readonly name = "lease_forfeiter";
  readonly description = "Forfeit expired leases (lessor)";
  readonly scheduleType = "deadline" as const;
  enabled = true;

  constructor(private mktPackageId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return signal.deadlineData?.deadlineType === "lease_forfeit";
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const tx = new Tx();
    forfeitLease(tx, this.mktPackageId, signal.deadlineData!.objectId);
    return tx;
  }
}
```

- [ ] **Step 2: Implement FleetDamageHandler**

```ts
// src/rules/fleet-damage.ts
import type { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "./interface.js";
import type { WatcherSignal, RuleConfig } from "../types.js";
import { createOrderFromDamageReport } from "../executor/ptb-builder.js";
import { Transaction as Tx } from "@mysten/sui/transactions";

export class FleetDamageHandler implements RuleHandler {
  readonly name = "fleet_damage";
  readonly description = "Create work order from fleet damage report";
  readonly scheduleType = "fleet" as const;
  enabled = true;

  constructor(private woPackageId: string, private boardId: string) {}

  async evaluate(signal: WatcherSignal, _config: RuleConfig): Promise<boolean> {
    return signal.type === "fleet" && !!signal.fleetData;
  }

  async buildTx(signal: WatcherSignal, _config: RuleConfig): Promise<Transaction> {
    const report = signal.fleetData!;
    const tx = new Tx();
    const deadline = Date.now() + 24 * 60 * 60 * 1000;
    createOrderFromDamageReport(
      tx, this.woPackageId, this.boardId,
      report.description, report.recipeId, report.quantity,
      "", // payment coin — resolved at runtime
      deadline, `fleet_damage_${Date.now()}`,
    );
    return tx;
  }
}
```

- [ ] **Step 3: Write and run tests for both**

Tests follow same pattern as other deadline/fleet handlers.

Run: `cd watcher && npx vitest run tests/rules/lease-forfeiter.test.ts tests/rules/fleet-damage.test.ts`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add watcher/src/rules/lease-forfeiter.ts watcher/src/rules/fleet-damage.ts watcher/tests/rules/
git commit -m "feat(watcher): add LeaseForfeiter and FleetDamageHandler"
```

---

### Task 17: Watcher Engine (Orchestrator)

**Files:**
- Create: `src/engine.ts`
- Create: `tests/engine.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/engine.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import { WatcherEngine } from "../src/engine.js";
import { RuleRegistry } from "../src/rules/registry.js";
import { createDb } from "../src/db/sqlite.js";
import { Transaction } from "@mysten/sui/transactions";
import type { RuleHandler } from "../src/rules/interface.js";
import type { WatcherConfig } from "../src/types.js";

function makeTestConfig(): WatcherConfig {
  return {
    network: "testnet",
    package_ids: {
      industrial_core: "0xCORE",
      work_order: "0xWO",
      marketplace: "0xMKT",
    },
    signer: { type: "single", keypath: "" },
    watch: {
      poll_interval_ms: 100,
      production_line_ids: ["0xLINE1"],
      work_order_board_id: "0xBOARD",
      marketplace_id: "0xMARKET",
      item_type_ids: [1],
    },
    gas: {
      pool_size: 5,
      min_balance_warn: 100000000,
      min_coin_balance: 5000000,
      auto_replenish: true,
    },
    rules: { output_withdrawer: { enabled: true } },
  };
}

describe("WatcherEngine", () => {
  let db: Database.Database;
  beforeEach(() => { db = createDb(":memory:"); });
  afterEach(() => db.close());

  it("dispatches event signals to matching rule handlers", async () => {
    const evaluateSpy = vi.fn().mockResolvedValue(true);
    const buildTxSpy = vi.fn().mockResolvedValue(new Transaction());
    const registry = new RuleRegistry();
    registry.register({
      name: "test_rule",
      description: "test",
      eventType: "ProductionCompletedEvent",
      enabled: true,
      evaluate: evaluateSpy,
      buildTx: buildTxSpy,
    });
    const engine = new WatcherEngine(makeTestConfig(), db, registry);
    await engine.dispatch({
      type: "event",
      eventData: {
        id: { txDigest: "0x1", eventSeq: "0" },
        type: "0xCORE::production_line::ProductionCompletedEvent",
        parsedJson: {},
        packageId: "0xCORE",
        transactionModule: "production_line",
        sender: "0x",
        bcs: "",
        timestampMs: "0",
      },
    });
    expect(evaluateSpy).toHaveBeenCalledOnce();
    expect(buildTxSpy).toHaveBeenCalledOnce();
  });

  it("skips rules that evaluate to false", async () => {
    const buildTxSpy = vi.fn();
    const registry = new RuleRegistry();
    registry.register({
      name: "skip_me",
      description: "test",
      eventType: "SomeEvent",
      enabled: true,
      evaluate: vi.fn().mockResolvedValue(false),
      buildTx: buildTxSpy,
    });
    const engine = new WatcherEngine(makeTestConfig(), db, registry);
    await engine.dispatch({
      type: "event",
      eventData: {
        id: { txDigest: "0x1", eventSeq: "0" },
        type: "0xCORE::m::SomeEvent",
        parsedJson: {},
        packageId: "0xCORE",
        transactionModule: "m",
        sender: "0x",
        bcs: "",
        timestampMs: "0",
      },
    });
    expect(buildTxSpy).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd watcher && npx vitest run tests/engine.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement src/engine.ts**

```ts
import type Database from "better-sqlite3";
import type { WatcherConfig, WatcherSignal } from "./types.js";
import type { RuleRegistry } from "./rules/registry.js";
import type { TxExecutor } from "./executor/tx-executor.js";

export class WatcherEngine {
  private txExecutor: TxExecutor | null = null;

  constructor(
    private config: WatcherConfig,
    private db: Database.Database,
    private registry: RuleRegistry,
  ) {}

  setTxExecutor(executor: TxExecutor): void {
    this.txExecutor = executor;
  }

  async dispatch(signal: WatcherSignal): Promise<void> {
    let handlers;

    if (signal.type === "event" && signal.eventData) {
      handlers = this.registry.getByEventType(signal.eventData.type);
    } else if (signal.type === "inventory") {
      handlers = this.registry.getByScheduleType("inventory");
    } else if (signal.type === "deadline") {
      handlers = this.registry.getByScheduleType("deadline");
    } else if (signal.type === "fleet") {
      handlers = this.registry.getByScheduleType("fleet");
    } else {
      return;
    }

    for (const handler of handlers) {
      const ruleConfig = this.config.rules[handler.name] ?? {
        enabled: true,
      };
      try {
        const shouldAct = await handler.evaluate(signal, ruleConfig);
        if (!shouldAct) continue;

        const tx = await handler.buildTx(signal, ruleConfig);

        if (this.txExecutor) {
          const result = await this.txExecutor.execute(
            handler.name,
            tx,
            JSON.stringify(signal),
          );
          if (result.success) {
            console.log(`[${handler.name}] TX success: ${result.digest}`);
          } else {
            console.error(`[${handler.name}] TX failed: ${result.error}`);
          }
        }
      } catch (err) {
        console.error(`[${handler.name}] Error:`, err);
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd watcher && npx vitest run tests/engine.test.ts`
Expected: ALL PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add watcher/src/engine.ts watcher/tests/engine.test.ts
git commit -m "feat(watcher): add WatcherEngine orchestrator"
```

---

### Task 18: Entry Point & Main Loop

**Files:**
- Create: `src/index.ts`

- [ ] **Step 1: Implement src/index.ts**

Main loop: poll events → dispatch → poll inventory → dispatch → check deadlines → dispatch. Fleet listener runs on its own interval.

See spec for full wiring — imports all modules, creates instances, registers enabled rules from config, runs graceful shutdown on SIGINT.

Key wiring points:
- `SuiClient` from `getFullnodeUrl(config.network)`
- `SingleKeypairProvider.fromKeystoreFile(config.signer.keypath)`
- `GasPool` initialized with `config.gas.*`
- `TxExecutor(client, gasPool, signer, db)`
- `RuleRegistry` with each rule registered only if `config.rules[name].enabled`
- `WatcherEngine(config, db, registry)` with `setTxExecutor()`
- Poll loop: `EventPoller.poll()` → `DeadlineScheduler.processEvents()` → dispatch events → `InventoryMonitor.poll()` → dispatch inventory → `DeadlineScheduler.getExpired()` → dispatch deadlines
- `FleetListener.start()` for mock mode
- SIGINT handler: `fleetListener.stop()`, `db.close()`

- [ ] **Step 2: Typecheck**

Run: `cd watcher && npx tsc --noEmit`
Expected: PASS

- [ ] **Step 3: Run all tests**

Run: `cd watcher && npx vitest run`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add watcher/src/index.ts
git commit -m "feat(watcher): add main entry point with poll loop"
```

---

### Task 19: Full Test Suite & Final Verification

- [ ] **Step 1: Run complete test suite**

Run: `cd watcher && npx vitest run --reporter=verbose`
Expected: ALL tests pass

- [ ] **Step 2: Typecheck**

Run: `cd watcher && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Build**

Run: `cd watcher && npx tsc`
Expected: `dist/` created

- [ ] **Step 4: Final commit**

```bash
git add watcher/
git commit -m "feat(watcher): complete off-chain watcher (Task 11-13)"
```

---

## Dependency Graph

```
Task 1 (scaffold)
  └→ Task 2 (types)
      ├→ Task 3 (SQLite)
      ├→ Task 4 (config)
      └→ Task 5 (signer)
           └→ Task 6 (gas pool)
                └→ Task 7 (tx executor)
                     └→ Task 8 (ptb builder)
                          ├→ Task 9  (event poller)
                          ├→ Task 10 (inventory monitor)
                          ├→ Task 11 (deadline scheduler)
                          └→ Task 12 (fleet listener)
                               └→ Task 13 (rule registry)
                                    ├→ Task 14 (production rules ×4)
                                    ├→ Task 15 (work order rules ×5)
                                    └→ Task 16 (lease + fleet rules ×2)
                                         └→ Task 17 (watcher engine)
                                              └→ Task 18 (entry point)
                                                   └→ Task 19 (final verify)
```

## Parallelization Opportunities

Tasks on the same dependency level can run as parallel subagents:
- **Level A**: Tasks 3, 4, 5 (SQLite, Config, Signer) — independent after Task 2
- **Level B**: Tasks 9, 10, 11, 12 (all pollers) — independent after Task 8
- **Level C**: Tasks 14, 15, 16 (all rule handler groups) — independent after Task 13

# Off-chain Watcher Design Spec

> Task 11-13: Watcher scaffold, TX Executor + Rule Matcher, Listeners
> Last updated: 2026-03-21 (post audit review)

## Overview

A Node.js long-running process that polls SUI on-chain events and object state, evaluates rule-based conditions, and automatically executes transactions against Industrial Auto OS contracts. SQLite for local state persistence.

## Prerequisites (Contract Fixes Required)

The following Move contract issues **must be resolved before watcher implementation**:

### P1. Shared object by-value consumption (CRITICAL)

6 functions consume shared objects by value — this **fails in on-chain PTBs** (works in test_scenario but not in production). Requires contract refactoring:

| Function | File | Shared Type | Fix |
|----------|------|-------------|-----|
| `delist_bpo` | marketplace.move:152 | `BpoListing` | Refactor to `&mut` + status flag or use owned objects |
| `buy_bpo` | marketplace.move:162 | `BpoListing` | Same |
| `delist_bpc` | marketplace.move:226 | `BpcListing` | Same |
| `buy_bpc` | marketplace.move:236 | `BpcListing` | Same |
| `return_lease` | lease.move:81 | `LeaseAgreement` | Same |
| `forfeit_lease` | lease.move:96 | `LeaseAgreement` | Same |

**Impact on watcher**: Rule #8 (LeaseForfeiter) is blocked until `forfeit_lease` is refactored.

### P2. `mock_fuel` missing `#[test_only]` (CRITICAL)

`mock_deposit_fuel` is `public fun` with no auth — anyone can add free fuel to any production line on-chain. Must add `#[test_only]` or delete before deployment.

### P3. `start_production_with_efficiency` unbounded ME/TE (HIGH)

Accepts arbitrary `me: u8, te: u8` without validation. An attacker can call with `me=99` to reduce material cost to 1%. Fix: make `public(package)` or add `assert!(me <= 25 && te <= 25)`.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Runtime | Node.js + SQLite | Zero-dependency, hackathon-friendly, `@mysten/sui` native support |
| Scope | Single keypair, multi production line | "One factory owner + AI butler" model; config lists watched object IDs |
| Architecture | Plugin interface (C), hardcoded impl (A) | Future-proof for custom rule modules; hackathon uses hardcoded logic |
| Gas management | Pre-split pool (20 coins), round-robin | Avoids object version conflict on rapid TX sequences |
| Event ingestion | Polling + cursor | SUI subscriptions don't guarantee delivery; cursor stored in SQLite for restart resilience |
| Deduplication | Atomic cursor+tx_log write in single SQLite transaction | Prevents re-processing on crash-restart |

## Architecture

```
┌─────────────────────────────────────────────┐
│              WatcherEngine                   │
│  ┌─────────┐  ┌──────────┐  ┌────────────┐ │
│  │ Poller   │→│ Dispatcher│→│ RuleHandler │ │
│  │ (cursor) │  │          │  │ (plugin IF) │ │
│  └─────────┘  └──────────┘  └─────┬──────┘ │
│                                    ↓         │
│  ┌─────────┐  ┌──────────┐  ┌────────────┐ │
│  │ GasPool  │←│TxExecutor │←│ PTBBuilder  │ │
│  │(split×20)│  │(retry+log)│  │            │ │
│  └─────────┘  └──────────┘  └────────────┘ │
│                     ↓                        │
│              ┌────────────┐                  │
│              │  SQLite DB  │                  │
│              │(cursor,logs)│                  │
│              └────────────┘                  │
└─────────────────────────────────────────────┘
```

### Data Flow

1. **EventPoller** polls `sui_queryEvents` with stored cursor → yields new events
2. **InventoryMonitor** polls `sui_getDynamicFieldObject` on production line Bag buffers → yields low-stock signals
3. **DeadlineScheduler** queries SQLite `deadlines` table → yields expiring work orders / leases
4. **FleetCmdListener** (mock mode) generates fake damage reports on interval
5. **Dispatcher** routes each signal to matching **RuleHandler**
6. **RuleHandler.evaluate()** checks config conditions (thresholds, filters)
7. **RuleHandler.buildTx()** returns a `Transaction` (PTB)
8. **TxExecutor** acquires gas coin from **GasPool**, signs via **SignerProvider**, submits TX
9. Cursor update + tx_log insert wrapped in **single SQLite transaction** (atomic dedup)

## Core Interfaces

### SignerProvider (future: multi-key)

```ts
interface SignerProvider {
  getSigner(context?: SignerContext): Promise<Keypair>;
  listSigners(): Promise<SignerInfo[]>;
}

interface SignerContext {
  ruleHandler: string;
  productionLineId?: string;
}

interface SignerInfo {
  address: string;
  label: string;
}
```

Hackathon implementation: `SingleKeypairProvider` loads from SUI keystore file.

### RuleHandler (future: plugin system)

```ts
interface RuleHandler {
  readonly name: string;
  readonly description: string;
  readonly eventType?: string;        // subscribe to specific event type
  readonly scheduleType?: 'inventory' | 'deadline' | 'fleet'; // non-event triggers
  enabled: boolean;

  evaluate(signal: WatcherSignal, config: RuleConfig): Promise<boolean>;
  buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction>;
}

interface WatcherSignal {
  type: 'event' | 'inventory' | 'deadline' | 'fleet';
  eventData?: SuiEvent;
  inventoryData?: InventorySnapshot;
  deadlineData?: DeadlineRecord;
  fleetData?: MockDamageReport;
}

interface RuleConfig {
  enabled: boolean;
  [key: string]: unknown;  // rule-specific config
}
```

### RuleRegistry (future: dynamic loader)

```ts
class RuleRegistry {
  register(handler: RuleHandler): void;
  getByEventType(type: string): RuleHandler[];
  getByScheduleType(type: string): RuleHandler[];
  listAll(): RuleHandler[];
}
```

Hackathon: `registerBuiltinRules()` registers all 11 handlers.
Future: `loadPluginDirectory(path)` dynamically imports JS modules.

## 11 Rule Handlers

| # | Handler | Trigger Source | On-chain Action | Config Keys | Notes |
|---|---------|---------------|-----------------|-------------|-------|
| 1 | TriggerEvaluator | InventoryMonitor (schedule) | `trigger_engine::execute_trigger` | `production_line_ids` | Polls TriggerRule objects, calls evaluate then execute. NOT triggered by TriggerFiredEvent (that's the output, not the input). Mutually exclusive with AutoRestockRule per line. |
| 2 | OutputWithdrawer | `ProductionCompletedEvent` | `production_line::withdraw_output` | — | Clears output buffer counter; actual items tracked off-chain. |
| 3 | AutoRestockRule | InventoryMonitor (low stock) | `production_line::start_production` | `threshold`, `production_line_ids` | Mutually exclusive with TriggerEvaluator per production line — config enforced. |
| 4 | OrderAcceptor | `WorkOrderCreated` | `work_order::accept_work_order` | `max_escrow`, `recipe_ids` | Watcher becomes acceptor — binds delivery + completion responsibility. |
| 5 | OrderCompleter | `WorkOrderDelivered` | `work_order::complete_work_order` | — | Only works for orders where watcher is the issuer. |
| 6 | AutoCompleteRule | DeadlineScheduler (72h+) | `work_order::auto_complete_work_order` | — | sender must == acceptor; watcher can only complete its own accepted orders. |
| 7 | ExpiredCleaner | DeadlineScheduler (expired) | `work_order::cancel_expired_order` | — | Permissionless — anyone can call. |
| 8 | LeaseForfeiter | DeadlineScheduler (lease expired) | `marketplace::forfeit_lease` | — | **BLOCKED** until P1 contract fix. sender must == lessor. |
| 9 | FleetDamageHandler | FleetCmdListener (mock) | `fleet_integration::create_order_from_damage_report` | `mock: bool`, `interval_ms` | Mock mode for hackathon demo. |
| 10 | ProductionCompleter | InventoryMonitor (job timer) | `production_line::complete_production` | — | Polls running production lines, calls complete_production when estimated_completion <= now. Without this, no ProductionCompletedEvent fires. |
| 11 | DeliveryHandler | DeadlineScheduler (accepted orders) | `work_order::deliver_work_order` | `auto_deliver: bool` | Completes the accept→deliver→complete lifecycle. sender must == acceptor. |

### TriggerEvaluator vs AutoRestockRule deconfliction

Both respond to low inventory. Config enforces mutual exclusivity per production line:

```yaml
rules:
  trigger_evaluator:
    enabled: true
    production_line_ids: ["0xAAA"]   # uses on-chain TriggerRule objects
  auto_restock:
    enabled: true
    production_line_ids: ["0xBBB"]   # uses off-chain threshold config
    threshold: 10
```

Watcher validates at startup: no production line ID appears in both.

## Pollers / Listeners

### EventPoller
- Calls `sui_queryEvents` with package filter + stored cursor
- Polls every `poll_interval_ms` (default 5000ms)
- Persists cursor to SQLite `cursors` table on each batch
- Cursor update is **atomic with tx_log insert** (single SQLite transaction) — prevents re-processing on crash
- Restart-safe: resumes from last cursor

### InventoryMonitor
- Polls `sui_getDynamicFieldObject` (NOT `sui_getObject`) for each production line ID in config
- Requires `item_type_ids` in config to know which Bag keys to query
- Also reads production line status to detect running jobs for ProductionCompleter
- Emits `WatcherSignal { type: 'inventory' }` when any material drops below configured threshold
- Poll interval: same as `poll_interval_ms`

### DeadlineScheduler
- On each EventPoller batch, extracts deadlines from `WorkOrderCreated` and `LeaseCreated` events → inserts into `deadlines` table
- **Startup backfill**: on first run, queries known `work_order_board_id` and lease objects to populate deadlines for pre-existing orders/leases
- Every poll cycle, queries deadlines where `deadline_at <= now`
- Emits signals for auto-complete (72h past acceptance), expired cancel, lease forfeit, delivery reminders

### FleetCmdListener (mock)
- When `fleet_damage.mock: true`, generates a fake `MockDamageReport` every `interval_ms`
- Report contains random recipe_id from config, random quantity, CRITICAL priority
- Calls `create_order_from_damage_report` with pre-funded escrow coin

## TX Executor

### Execution Flow
1. Receive `Transaction` from RuleHandler
2. Acquire gas coin from GasPool (round-robin)
3. Sign with SignerProvider
4. Submit via `sui_executeTransactionBlock`
5. On failure: retry up to 3 times with exponential backoff (1s, 2s, 4s)
6. Log result to `tx_log` (digest, status, error, gas_used, gas_coin_id, timestamp)
7. Update gas coin's `(objectId, version, digest)` triple from `effects.mutated` in TX response (NOT via separate RPC call)
8. Release gas coin back to pool

### Error Handling
- Object version conflict → retry with refreshed object ref
- Insufficient gas → log warning, mark gas coin as depleted, try next coin
- Abort code → log with decoded error, no retry (on-chain logic rejected the TX)
- Network error → retry with backoff

## Gas Pool

### Initialization
1. On startup, query signer's SUI coins
2. If fewer than `pool_size` coins exist, split largest coin into `pool_size` chunks
3. Each chunk ≈ total_balance / pool_size (minimum 0.05 SUI each)

### Runtime
- Round-robin assignment: `coins[nextIndex++ % pool_size]`
- After TX, update coin's `(objectId, version, digest)` from `effects.mutated` (avoids extra RPC + stale cache)
- When any coin's balance < `min_coin_balance`, merge all small coins + re-split

### Replenish
- When total pool balance < `min_balance_warn`, log WARNING
- When total pool balance < `min_balance_warn / 2`, pause rule execution, log CRITICAL

## SQLite Schema

```sql
CREATE TABLE IF NOT EXISTS cursors (
  event_type TEXT PRIMARY KEY,
  cursor_id  TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS tx_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  rule_name   TEXT NOT NULL,
  tx_digest   TEXT,
  status      TEXT NOT NULL,  -- 'success' | 'failed' | 'retrying'
  error       TEXT,
  signal_data TEXT,           -- JSON of triggering signal
  gas_coin_id TEXT,           -- gas coin used for this TX
  gas_used    INTEGER,        -- actual gas consumed (MIST)
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS deadlines (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  object_id     TEXT NOT NULL,
  object_type   TEXT NOT NULL,    -- 'work_order' | 'lease'
  deadline_type TEXT NOT NULL,    -- 'deliver' | 'auto_complete' | 'expire' | 'lease_forfeit'
  deadline_at   INTEGER NOT NULL,
  processed     INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  UNIQUE(object_id, deadline_type)
);

CREATE INDEX idx_deadlines_pending ON deadlines(deadline_at) WHERE processed = 0;
```

## Config Format (YAML)

```yaml
network: testnet
package_ids:
  industrial_core: "0x..."
  work_order: "0x..."
  marketplace: "0x..."

signer:
  type: single            # future: vault, multi
  keypath: ~/.sui/sui.keystore

watch:
  poll_interval_ms: 5000
  production_line_ids:
    - "0x..."
  work_order_board_id: "0x..."
  marketplace_id: "0x..."
  item_type_ids:           # Bag keys for InventoryMonitor
    - "ammo_casing"
    - "refined_ore"
    - "fuel_cell"

gas:
  pool_size: 20
  min_balance_warn: 100000000   # 0.1 SUI
  min_coin_balance: 5000000     # 0.005 SUI per coin — triggers merge+re-split
  auto_replenish: true

rules:
  trigger_evaluator:
    enabled: true
    production_line_ids: ["0x..."]  # mutually exclusive with auto_restock
  output_withdrawer:
    enabled: true
  auto_restock:
    enabled: true
    threshold: 10
    production_line_ids: ["0x..."]  # mutually exclusive with trigger_evaluator
  order_acceptor:
    enabled: true
    max_escrow: 5000000000      # 5 SUI
    recipe_ids: []              # empty = accept all
  order_completer:
    enabled: true
  auto_complete:
    enabled: true
  expired_cleaner:
    enabled: true
  lease_forfeiter:
    enabled: false              # BLOCKED until P1 contract fix
  fleet_damage:
    enabled: true
    mock: true
    interval_ms: 30000
  production_completer:
    enabled: true
  delivery_handler:
    enabled: true
    auto_deliver: true
```

## Directory Structure

```
watcher/
├── src/
│   ├── index.ts                  # entry point, CLI args
│   ├── engine.ts                 # WatcherEngine orchestrator
│   ├── config.ts                 # YAML loader + validation
│   ├── types.ts                  # shared types/interfaces
│   ├── signer/
│   │   ├── interface.ts          # SignerProvider interface
│   │   └── single.ts            # SingleKeypairProvider
│   ├── poller/
│   │   ├── event-poller.ts      # SUI event polling + cursor
│   │   ├── inventory-monitor.ts # production line buffer check via getDynamicFieldObject
│   │   ├── deadline-scheduler.ts # deadline-based triggers + startup backfill
│   │   └── fleet-listener.ts    # mock fleet damage reports
│   ├── rules/
│   │   ├── interface.ts         # RuleHandler interface
│   │   ├── registry.ts          # RuleRegistry (plugin loader)
│   │   ├── trigger-evaluator.ts # polls TriggerRule → evaluate → execute
│   │   ├── output-withdrawer.ts
│   │   ├── auto-restock.ts
│   │   ├── order-acceptor.ts
│   │   ├── order-completer.ts
│   │   ├── auto-complete.ts
│   │   ├── expired-cleaner.ts
│   │   ├── lease-forfeiter.ts   # BLOCKED until P1 fix
│   │   ├── fleet-damage.ts
│   │   ├── production-completer.ts  # NEW: polls running jobs → complete_production
│   │   └── delivery-handler.ts      # NEW: auto deliver for accepted orders
│   ├── executor/
│   │   ├── tx-executor.ts       # sign + submit + retry
│   │   ├── ptb-builder.ts       # PTB construction helpers (moveCall wrappers, coin splitting)
│   │   └── gas-pool.ts          # coin split/merge/round-robin
│   └── db/
│       ├── sqlite.ts            # connection + helpers
│       └── migrations.ts        # schema creation
├── config.example.yaml
├── package.json
└── tsconfig.json
```

## Constraints & Known Limitations

- `auto_complete_work_order`: sender must be the acceptor — watcher can only complete orders it accepted
- `deliver_work_order`: sender must be the acceptor — watcher can only deliver for orders it accepted
- `forfeit_lease`: sender must be the lessor — watcher can only forfeit leases it created; **BLOCKED by P1**
- `complete_production`: must be called before `withdraw_output` — ProductionCompleter (rule #10) is essential
- Gas coin split happens at startup; each coin ~0.05 SUI minimum
- Polling cursor persisted in SQLite; restart-safe via atomic cursor+tx_log writes
- No WebSocket: SUI subscriptions don't guarantee delivery
- InventoryMonitor requires `sui_getDynamicFieldObject` with typed Bag keys (not plain `getObject`)
- TriggerEvaluator and AutoRestockRule are mutually exclusive per production line (validated at startup)
- `daily_rate` in LeaseAgreement is stored but never charged — design gap in contract, watcher ignores it

## Audit Trail

### move-code-quality (2026-03-21)

Key findings incorporated:
- C3 (shared object by value) → documented as P1 prerequisite
- Edition "2024.beta" → noted for contract fix pass
- Loop macros, error naming, test naming → deferred to code quality pass

### sui-red-team (2026-03-21)

Key findings incorporated:
- Finding 1 (mock_fuel no auth) → documented as P2 prerequisite
- Finding 2 (unbounded ME/TE) → documented as P3 prerequisite
- Finding 5/6 (shared object contention) → same as C3, standard Sui behavior
- Finding 11 (TOCTOU verified safe) → confirmed trigger_engine design is correct
- Finding 14 (daily_rate unused) → documented in constraints

### Generic code-reviewer (2026-03-21)

Key findings incorporated:
- TriggerExecutor trigger direction fix → rule renamed to TriggerEvaluator, uses schedule not event
- Missing ProductionCompleter → added as rule #10
- Missing DeliveryHandler → added as rule #11
- Dedup strategy → atomic SQLite transaction for cursor + tx_log
- Gas coin refresh from TX effects → specified in TxExecutor flow
- InventoryMonitor getDynamicFieldObject → corrected in spec
- DeadlineScheduler startup backfill → added

# Eve Eyes API Integration — Design Spec

**Date:** 2026-04-01
**Scope:** Integrate Eve Eyes API into Industrial_Auto_OS frontend + watcher
**Priority:** Hackathon demo (P0 only)

## Overview

Add 3 new "intel" panes to the frontend dashboard that consume Eve Eyes API data (killmail feed, building leaderboard, transaction explorer). A thin proxy in the watcher handles authenticated indexer requests server-side to keep the API key off the client.

## Architecture

```
Frontend (React)                    Watcher (Express)              Eve Eyes API
┌─────────────────┐                ┌──────────────┐              ┌──────────────┐
│ KillmailFeed    │──public GET──────────────────────────────────▶│ /killmails   │
│ Leaderboard     │──public GET──────────────────────────────────▶│ /leaderboard │
│ TxExplorer      │──public GET──────────────────────────────────▶│ /tx-blocks/  │
│                 │               │              │              │   {digest}    │
│                 │──proxy GET───▶│ /eve-eyes/*  │──API key────▶│ /tx-blocks   │
│                 │               │ (2 routes)   │              │ /move-calls  │
└─────────────────┘                └──────────────┘              └──────────────┘
```

**Principle:** Frontend never touches the API key. Public endpoints hit Eve Eyes directly; page 4+ indexer queries go through the watcher proxy.

## 1. Eve Eyes API Client (Frontend)

**File:** `frontend/src/lib/eveEyes.ts`

Lightweight fetch wrapper:

```ts
const EVE_EYES_URL = import.meta.env.VITE_EVE_EYES_URL; // https://eve-eyes.d0v.xyz
const WATCHER_URL = import.meta.env.VITE_WATCHER_URL;    // reuse existing

// Public endpoints — direct
export async function fetchKillmails(params) { ... }
export async function fetchBuildingLeaderboard(params) { ... }
export async function fetchTransactionBlockDetail(digest) { ... }
export async function fetchMoveCallDetail(txDigest, callIndex) { ... }
export async function fetchModuleCallCounts() { ... }

// Proxied endpoints — through watcher
export async function fetchTransactionBlocks(params) { ... }
export async function fetchMoveCalls(params) { ... }
```

Error handling: all functions return `{ data, error }` tuple. On fetch failure or non-2xx, return `{ data: null, error: string }`.

## 2. Watcher Proxy

**File:** `watcher/src/api/eve-eyes-proxy.ts`

Two GET routes mounted on the existing Express server:

| Route | Forwards to |
|-------|-------------|
| `GET /eve-eyes/transaction-blocks` | `GET /api/indexer/transaction-blocks` |
| `GET /eve-eyes/move-calls` | `GET /api/indexer/move-calls` |

### Security

- **API key injection:** Server-side `Authorization: ApiKey <key>` header from config
- **Query param whitelist:** Only forward allowed params:
  - transaction-blocks: `page`, `pageSize`, `network`, `senderAddress`, `status`, `digest`, `transactionKind`, `checkpoint`
  - move-calls: `page`, `pageSize`, `network`, `senderAddress`, `status`, `txDigest`, `packageId`, `moduleName`, `functionName`, `callIndex`, `includeActionSummary`
- **No path traversal:** Routes are hardcoded, not dynamic
- **Error passthrough:** Forward Eve Eyes error responses as-is (status code + body)

### Config

**`config.yaml` addition:**
```yaml
eve_eyes:
  base_url: https://eve-eyes.d0v.xyz
  api_key: <from env or config, gitignored>
```

**`config.example.yaml` addition:**
```yaml
eve_eyes:
  base_url: https://eve-eyes.d0v.xyz
  api_key: YOUR_API_KEY_HERE
```

The `api_key` can also come from env var `EVE_EYES_API_KEY` (takes precedence over config file).

## 3. Frontend Hooks

Four new hooks following existing React Query patterns:

| Hook | Endpoint | Source | Refetch | Notes |
|------|----------|--------|---------|-------|
| `useKillmails(limit?, status?)` | `/api/indexer/killmails` | Public direct | 10s | Auto-refresh feed |
| `useBuildingLeaderboard(limit?, moduleName?)` | `/api/v1/indexer/building-leaderboard` | Public direct | 30s | Module type filter |
| `useTransactionBlocks(filters, page, pageSize)` | `/api/indexer/transaction-blocks` | page ≤ 3: public / page ≥ 4: proxy | Manual (user-driven pagination) | Paginated table |
| `useMoveCallDetail(txDigest, callIndex)` | `/api/indexer/move-calls/{txDigest}/{callIndex}` | Public direct | On-demand | Single move call detail (expand on click) |
| `useMoveCallsForTx(txDigest)` | `/api/indexer/transaction-blocks/{digest}/move-calls?includeActionSummary=1` | Public direct | On-demand | All move calls for a tx (expand on click) |

### Error Handling

- `retry: 1` (not default 3 — external API, don't spam)
- `staleTime: 5000` minimum (reduce unnecessary refetches)
- All hooks return `{ data, isLoading, isError, error }` per React Query standard
- Error state renders "Intel unavailable" in pane (not a crash)

## 4. Frontend Panes

Three new panes under `intel` category:

### 4.1 KillmailFeed

- **Category:** `intel`
- **Default size:** `{ w: 4, h: 6 }`
- **Min size:** `{ w: 3, h: 4 }`
- **Features:**
  - Scrollable killmail list (most recent first)
  - Each row: timestamp, killer label, victim label, status badge
  - Status filter toggle: all / resolved / pending
  - Limit selector: 10 / 20 / 50
  - Auto-refresh 10s with visual indicator
  - "Intel unavailable" fallback on API error

### 4.2 BuildingLeaderboard

- **Category:** `intel`
- **Default size:** `{ w: 4, h: 6 }`
- **Min size:** `{ w: 3, h: 4 }`
- **Features:**
  - Module type selector: all / assembly / gate / network_node / storage_unit / turret
  - Ranked table: #, owner character, wallet address (truncated), count
  - Limit selector: 10 / 25 / 50
  - Auto-refresh 30s
  - "Intel unavailable" fallback on API error

### 4.3 TransactionExplorer

- **Category:** `intel`
- **Default size:** `{ w: 6, h: 8 }`
- **Min size:** `{ w: 4, h: 5 }`
- **Features:**
  - Filter bar: sender address, status (success/failure), digest search
  - Paginated table: digest (truncated + copy), sender, status, timestamp, tx kind
  - Page 1-3 public, page 4+ through proxy (transparent to user)
  - Click row → expand inline:
    - Move calls list for that tx
    - Each move call shows: package/module/function, action summary (if available)
    - Click move call → detail with parsed entities + raw call payload
  - "Intel unavailable" fallback on API error

## 5. Pane Registry Update

**File:** `frontend/src/config/paneRegistry.ts`

Add `intel` category and 3 new entries:

```ts
{ id: "killmail-feed",        title: "Killmail Feed",        category: "intel", ... }
{ id: "building-leaderboard", title: "Building Leaderboard", category: "intel", ... }
{ id: "tx-explorer",          title: "Transaction Explorer",  category: "intel", ... }
```

## 6. Environment & Config Changes

### Frontend `.env` addition

```
VITE_EVE_EYES_URL=https://eve-eyes.d0v.xyz
```

### Watcher `config.yaml` addition

```yaml
eve_eyes:
  base_url: https://eve-eyes.d0v.xyz
  api_key: eve_ak_OGg2rSPof-S_13eN_kpDeIw4-rG5_q8leYZhdL2IV5w
```

### Watcher env var override

```
EVE_EYES_API_KEY=eve_ak_...  # overrides config.yaml
```

## 7. Styling

All panes use existing HUD amber theme (`--hud-amber`, `--hud-bg`, etc.) and CSS module pattern consistent with existing panes.

## 8. File Inventory

### New files (~10)

| File | Purpose |
|------|---------|
| `frontend/src/lib/eveEyes.ts` | Eve Eyes API client |
| `frontend/src/hooks/useEveEyes.ts` | 4 React Query hooks |
| `frontend/src/panes/KillmailFeed.tsx` | Killmail feed pane |
| `frontend/src/panes/KillmailFeed.module.css` | Killmail styles |
| `frontend/src/panes/BuildingLeaderboard.tsx` | Leaderboard pane |
| `frontend/src/panes/BuildingLeaderboard.module.css` | Leaderboard styles |
| `frontend/src/panes/TransactionExplorer.tsx` | Tx explorer pane |
| `frontend/src/panes/TransactionExplorer.module.css` | Tx explorer styles |
| `watcher/src/api/eve-eyes-proxy.ts` | Proxy routes |

### Modified files (~4)

| File | Change |
|------|--------|
| `frontend/src/config/paneRegistry.ts` | Add 3 panes + `intel` category |
| `frontend/.env` | Add `VITE_EVE_EYES_URL` |
| `watcher/src/api/server.ts` | Mount proxy routes |
| `watcher/config.example.yaml` | Add `eve_eyes` section |

### Estimated LOC: ~450-550 new lines

## 9. Out of Scope

- Eve Eyes JWT wallet login flow (P1 — future)
- World route / system search panes (P1 — future)
- ModuleSummary / ModuleCallCounts pane (P1 — future)
- `@mysten/dapp-kit` → `@mysten/dapp-kit-react` migration (separate task)
- Watcher consuming Eve Eyes data for rule evaluation

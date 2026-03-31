# Eve Eyes API Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Eve Eyes API into Industrial_Auto_OS with 3 new intel panes (Killmail Feed, Building Leaderboard, Transaction Explorer) and a watcher proxy for authenticated indexer queries.

**Architecture:** Frontend directly calls public Eve Eyes endpoints for killmails, leaderboard, and single-tx detail. For paginated indexer queries (page 4+), requests go through a watcher proxy that injects the API key server-side. All new panes live under a new `intel` category.

**Tech Stack:** React 18, @tanstack/react-query, Express 5, CSS Modules (HUD amber theme)

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `frontend/src/lib/eveEyes.ts` | Eve Eyes API client — fetch wrappers for all endpoints |
| `frontend/src/hooks/useEveEyes.ts` | 5 React Query hooks for Eve Eyes data |
| `frontend/src/panes/KillmailFeed.tsx` | Killmail feed pane component |
| `frontend/src/panes/KillmailFeed.module.css` | Killmail feed styles |
| `frontend/src/panes/BuildingLeaderboard.tsx` | Building leaderboard pane component |
| `frontend/src/panes/BuildingLeaderboard.module.css` | Building leaderboard styles |
| `frontend/src/panes/TransactionExplorer.tsx` | Transaction explorer pane component |
| `frontend/src/panes/TransactionExplorer.module.css` | Transaction explorer styles |
| `watcher/src/api/eve-eyes-proxy.ts` | Express router — 2 proxy routes with API key injection |

### Modified Files

| File | Change |
|------|--------|
| `frontend/src/config/paneRegistry.ts` | Add `intel` to category union, add 3 pane entries |
| `frontend/.env` | Add `VITE_EVE_EYES_URL` |
| `watcher/src/api/server.ts` | Mount eve-eyes proxy router |
| `watcher/src/index.ts` | Pass eve_eyes config to API router |
| `watcher/src/types.ts` | Add `EveEyesConfig` interface |
| `watcher/config.example.yaml` | Add `eve_eyes` section |

---

### Task 1: Watcher Proxy — Types + Config

**Files:**
- Modify: `watcher/src/types.ts:71-79`
- Modify: `watcher/config.example.yaml:66-73`

- [ ] **Step 1: Add EveEyesConfig type**

In `watcher/src/types.ts`, add after the `EveIntegrationConfig` interface (line 79):

```typescript
// ─── Eve Eyes API Types ──────────────────────
export interface EveEyesConfig {
  base_url: string;
  api_key: string;
}
```

- [ ] **Step 2: Add eve_eyes to config.example.yaml**

Append to `watcher/config.example.yaml`:

```yaml
eve_eyes:
  base_url: https://eve-eyes.d0v.xyz
  api_key: YOUR_EVE_EYES_API_KEY
```

- [ ] **Step 3: Commit**

```bash
git add watcher/src/types.ts watcher/config.example.yaml
git commit -m "feat(watcher): add EveEyesConfig type and config example"
```

---

### Task 2: Watcher Proxy — Router

**Files:**
- Create: `watcher/src/api/eve-eyes-proxy.ts`
- Modify: `watcher/src/api/server.ts`
- Modify: `watcher/src/index.ts:115-125`

- [ ] **Step 1: Create the proxy router**

Create `watcher/src/api/eve-eyes-proxy.ts`:

```typescript
import { Router } from "express";
import type { EveEyesConfig } from "../types.js";

const TX_BLOCKS_ALLOWED = new Set([
  "page", "pageSize", "network", "senderAddress", "status",
  "digest", "transactionKind", "checkpoint",
]);

const MOVE_CALLS_ALLOWED = new Set([
  "page", "pageSize", "network", "senderAddress", "status",
  "txDigest", "packageId", "moduleName", "functionName",
  "callIndex", "includeActionSummary",
]);

function filterParams(
  raw: Record<string, unknown>,
  allowed: Set<string>,
): URLSearchParams {
  const params = new URLSearchParams();
  for (const [key, val] of Object.entries(raw)) {
    if (allowed.has(key) && typeof val === "string") {
      params.set(key, val);
    }
  }
  return params;
}

export function createEveEyesProxy(config: EveEyesConfig): Router {
  const router = Router();
  const apiKey =
    process.env.EVE_EYES_API_KEY ?? config.api_key;
  const baseUrl = config.base_url.replace(/\/$/, "");

  async function proxyGet(
    upstream: string,
    allowed: Set<string>,
    query: Record<string, unknown>,
    res: import("express").Response,
  ): Promise<void> {
    const params = filterParams(query, allowed);
    const url = `${baseUrl}${upstream}?${params}`;
    try {
      const upstream_res = await fetch(url, {
        headers: { Authorization: `ApiKey ${apiKey}` },
      });
      const body = await upstream_res.text();
      res.status(upstream_res.status).type("json").send(body);
    } catch (err) {
      res.status(502).json({
        error: "Eve Eyes API unavailable",
        detail: err instanceof Error ? err.message : String(err),
      });
    }
  }

  router.get("/transaction-blocks", (req, res) => {
    proxyGet(
      "/api/indexer/transaction-blocks",
      TX_BLOCKS_ALLOWED,
      req.query as Record<string, unknown>,
      res,
    );
  });

  router.get("/move-calls", (req, res) => {
    proxyGet(
      "/api/indexer/move-calls",
      MOVE_CALLS_ALLOWED,
      req.query as Record<string, unknown>,
      res,
    );
  });

  return router;
}
```

- [ ] **Step 2: Update server.ts to accept optional eveEyesConfig**

Modify `watcher/src/api/server.ts` — update the `createApiRouter` signature and mount the proxy. The function signature changes from:

```typescript
export function createApiRouter(db: Database, registry: RuleRegistry): Router {
```

to:

```typescript
import { createEveEyesProxy } from "./eve-eyes-proxy.js";
import type { EveEyesConfig } from "../types.js";

export function createApiRouter(
  db: Database,
  registry: RuleRegistry,
  eveEyesConfig?: EveEyesConfig,
): Router {
```

And at the end of `createApiRouter`, before `return router;`, add:

```typescript
  if (eveEyesConfig) {
    router.use("/eve-eyes", createEveEyesProxy(eveEyesConfig));
  }
```

- [ ] **Step 3: Update index.ts to pass eve_eyes config**

In `watcher/src/index.ts`, change line 121 from:

```typescript
  apiApp.use("/", createApiRouter(db, registry));
```

to:

```typescript
  const eveEyesConfig = (config as any).eve_eyes as import("./types.js").EveEyesConfig | undefined;
  apiApp.use("/", createApiRouter(db, registry, eveEyesConfig));
```

- [ ] **Step 4: Verify watcher builds**

Run: `cd watcher && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add watcher/src/api/eve-eyes-proxy.ts watcher/src/api/server.ts watcher/src/index.ts
git commit -m "feat(watcher): add Eve Eyes proxy routes with API key injection"
```

---

### Task 3: Frontend — Eve Eyes API Client

**Files:**
- Create: `frontend/src/lib/eveEyes.ts`
- Modify: `frontend/src/lib/constants.ts`
- Modify: `frontend/.env`

- [ ] **Step 1: Add env var to .env**

Append to `frontend/.env`:

```
VITE_EVE_EYES_URL=https://eve-eyes.d0v.xyz
```

- [ ] **Step 2: Add EVE_EYES_URL to constants.ts**

Add after `WATCHER_URL` line in `frontend/src/lib/constants.ts`:

```typescript
export const EVE_EYES_URL = import.meta.env.VITE_EVE_EYES_URL ?? "https://eve-eyes.d0v.xyz";
```

- [ ] **Step 3: Create the API client**

Create `frontend/src/lib/eveEyes.ts`:

```typescript
import { EVE_EYES_URL, WATCHER_URL } from "./constants";

// ─── Types ──────────────────────────────────

export interface Killmail {
  killmailItemId: string;
  killTimestamp: string;
  killer: { label: string };
  victim: { label: string };
  status?: string;
}

export interface LeaderboardEntry {
  owner?: string;
  wallet?: string;
  count?: number;
  [key: string]: unknown;
}

export interface TransactionBlock {
  digest: string;
  sender?: string;
  status?: string;
  transactionKind?: string;
  transactionTime?: string;
  rawContent?: unknown;
  effects?: unknown;
  events?: unknown;
}

export interface MoveCallItem {
  packageId?: string;
  moduleName?: string;
  functionName?: string;
  callIndex?: number;
  actionSummary?: string;
  actionEntities?: unknown[];
  rawCall?: unknown;
}

export interface PaginatedResponse<T> {
  items: T[];
  pagination?: {
    page: number;
    pageSize: number;
    total?: number;
    hasMore?: boolean;
  };
}

// ─── Helpers ────────────────────────────────

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Eve Eyes API: ${res.status} ${res.statusText}`);
  }
  return res.json();
}

function qs(params: Record<string, string | number | undefined>): string {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== "") sp.set(k, String(v));
  }
  return sp.toString();
}

// ─── Public Endpoints (direct) ──────────────

export function fetchKillmails(params?: {
  limit?: number;
  status?: string;
}): Promise<{ items: Killmail[] }> {
  const q = qs({ limit: params?.limit, status: params?.status });
  return fetchJson(`${EVE_EYES_URL}/api/indexer/killmails${q ? `?${q}` : ""}`);
}

export function fetchBuildingLeaderboard(params?: {
  limit?: number;
  moduleName?: string;
}): Promise<{ leaderboard: LeaderboardEntry[] }> {
  const q = qs({ limit: params?.limit, moduleName: params?.moduleName });
  return fetchJson(`${EVE_EYES_URL}/api/v1/indexer/building-leaderboard${q ? `?${q}` : ""}`);
}

export function fetchTransactionBlockDetail(
  digest: string,
): Promise<{ item: TransactionBlock }> {
  return fetchJson(`${EVE_EYES_URL}/api/indexer/transaction-blocks/${encodeURIComponent(digest)}`);
}

export function fetchMoveCallsForTx(
  digest: string,
): Promise<{ items: MoveCallItem[] }> {
  return fetchJson(
    `${EVE_EYES_URL}/api/indexer/transaction-blocks/${encodeURIComponent(digest)}/move-calls?includeActionSummary=1`,
  );
}

export function fetchMoveCallDetail(
  txDigest: string,
  callIndex: number,
): Promise<{ item: MoveCallItem }> {
  return fetchJson(
    `${EVE_EYES_URL}/api/indexer/move-calls/${encodeURIComponent(txDigest)}/${callIndex}`,
  );
}

export function fetchModuleCallCounts(): Promise<{ modules: unknown[] }> {
  return fetchJson(`${EVE_EYES_URL}/api/indexer/module-call-counts`);
}

// ─── Proxied Endpoints (through watcher) ────

export function fetchTransactionBlocks(params: {
  page?: number;
  pageSize?: number;
  senderAddress?: string;
  status?: string;
  digest?: string;
}): Promise<PaginatedResponse<TransactionBlock>> {
  const page = params.page ?? 1;
  // Page 1-3: direct to Eve Eyes (public). Page 4+: through watcher proxy.
  const base = page <= 3 ? EVE_EYES_URL + "/api/indexer" : WATCHER_URL + "/eve-eyes";
  const q = qs({
    page,
    pageSize: params.pageSize ?? 20,
    senderAddress: params.senderAddress,
    status: params.status,
    digest: params.digest,
  });
  return fetchJson(`${base}/transaction-blocks?${q}`);
}

export function fetchMoveCalls(params: {
  page?: number;
  pageSize?: number;
  packageId?: string;
  moduleName?: string;
  functionName?: string;
}): Promise<PaginatedResponse<MoveCallItem>> {
  const page = params.page ?? 1;
  const base = page <= 3 ? EVE_EYES_URL + "/api/indexer" : WATCHER_URL + "/eve-eyes";
  const q = qs({
    page,
    pageSize: params.pageSize ?? 20,
    packageId: params.packageId,
    moduleName: params.moduleName,
    functionName: params.functionName,
  });
  return fetchJson(`${base}/move-calls?${q}`);
}
```

- [ ] **Step 4: Verify frontend builds**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add frontend/src/lib/eveEyes.ts frontend/src/lib/constants.ts frontend/.env
git commit -m "feat(frontend): add Eve Eyes API client with public + proxy fetch"
```

---

### Task 4: Frontend — React Query Hooks

**Files:**
- Create: `frontend/src/hooks/useEveEyes.ts`

- [ ] **Step 1: Create the hooks file**

Create `frontend/src/hooks/useEveEyes.ts`:

```typescript
import { useQuery } from "@tanstack/react-query";
import {
  fetchKillmails,
  fetchBuildingLeaderboard,
  fetchTransactionBlocks,
  fetchMoveCallsForTx,
  fetchMoveCallDetail,
  type Killmail,
  type LeaderboardEntry,
  type TransactionBlock,
  type MoveCallItem,
  type PaginatedResponse,
} from "../lib/eveEyes";

export function useKillmails(params?: { limit?: number; status?: string }) {
  return useQuery({
    queryKey: ["eve-eyes-killmails", params],
    queryFn: (): Promise<{ items: Killmail[] }> => fetchKillmails(params),
    refetchInterval: 10_000,
    retry: 1,
    staleTime: 5_000,
  });
}

export function useBuildingLeaderboard(params?: {
  limit?: number;
  moduleName?: string;
}) {
  return useQuery({
    queryKey: ["eve-eyes-leaderboard", params],
    queryFn: (): Promise<{ leaderboard: LeaderboardEntry[] }> =>
      fetchBuildingLeaderboard(params),
    refetchInterval: 30_000,
    retry: 1,
    staleTime: 10_000,
  });
}

export function useTransactionBlocks(params: {
  page?: number;
  pageSize?: number;
  senderAddress?: string;
  status?: string;
  digest?: string;
}) {
  return useQuery({
    queryKey: ["eve-eyes-tx-blocks", params],
    queryFn: (): Promise<PaginatedResponse<TransactionBlock>> =>
      fetchTransactionBlocks(params),
    retry: 1,
    staleTime: 5_000,
  });
}

export function useMoveCallsForTx(digest: string | null) {
  return useQuery({
    queryKey: ["eve-eyes-move-calls-tx", digest],
    queryFn: (): Promise<{ items: MoveCallItem[] }> =>
      fetchMoveCallsForTx(digest!),
    enabled: !!digest,
    retry: 1,
    staleTime: 60_000,
  });
}

export function useMoveCallDetail(
  txDigest: string | null,
  callIndex: number | null,
) {
  return useQuery({
    queryKey: ["eve-eyes-move-call-detail", txDigest, callIndex],
    queryFn: (): Promise<{ item: MoveCallItem }> =>
      fetchMoveCallDetail(txDigest!, callIndex!),
    enabled: !!txDigest && callIndex !== null,
    retry: 1,
    staleTime: 60_000,
  });
}
```

- [ ] **Step 2: Verify frontend builds**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add frontend/src/hooks/useEveEyes.ts
git commit -m "feat(frontend): add 5 React Query hooks for Eve Eyes API"
```

---

### Task 5: KillmailFeed Pane

**Files:**
- Create: `frontend/src/panes/KillmailFeed.tsx`
- Create: `frontend/src/panes/KillmailFeed.module.css`

- [ ] **Step 1: Create the CSS module**

Create `frontend/src/panes/KillmailFeed.module.css`:

```css
.container { display: flex; flex-direction: column; gap: 8px; }
.filters { display: flex; gap: 6px; align-items: center; }
.select { padding: 3px 6px; font-size: 10px; font-family: var(--font-mono); background: var(--bg-deep); border: 1px solid var(--border); color: var(--text-primary); border-radius: 2px; }
.list { display: flex; flex-direction: column; gap: 2px; overflow-y: auto; }
.row { display: flex; align-items: center; gap: 8px; padding: 5px 8px; background: var(--bg-deep); border: 1px solid var(--border); border-radius: 2px; font-size: 10px; }
.row:hover { border-color: var(--hud-amber); }
.timestamp { flex: 0 0 110px; color: var(--text-muted); font-family: var(--font-mono); font-size: 9px; }
.killer { color: var(--status-error); font-weight: 600; }
.vs { color: var(--text-muted); font-size: 9px; }
.victim { color: var(--text-secondary); }
.statusTag { margin-left: auto; font-size: 9px; text-transform: uppercase; letter-spacing: 0.5px; padding: 1px 4px; border-radius: 2px; border: 1px solid var(--border); }
.statusResolved { color: var(--status-ok); border-color: var(--status-ok); }
.statusPending { color: var(--hud-amber); border-color: var(--hud-amber); }
.unavailable { color: var(--status-error); font-size: 11px; padding: 8px; text-align: center; background: var(--bg-deep); border: 1px solid var(--status-error); border-radius: 2px; }
.empty { color: var(--text-muted); font-size: 11px; padding: 8px 0; }
.refreshing { font-size: 9px; color: var(--hud-amber); opacity: 0.6; }
```

- [ ] **Step 2: Create the component**

Create `frontend/src/panes/KillmailFeed.tsx`:

```tsx
import { useState } from "react";
import { useKillmails } from "../hooks/useEveEyes";
import styles from "./KillmailFeed.module.css";

export function KillmailFeed() {
  const [statusFilter, setStatusFilter] = useState("");
  const [limit, setLimit] = useState(20);

  const { data, isError, isFetching } = useKillmails({
    limit,
    status: statusFilter || undefined,
  });

  if (isError) {
    return (
      <div className={styles.container}>
        <div className={styles.unavailable}>Intel Unavailable</div>
      </div>
    );
  }

  const killmails = data?.items ?? [];

  return (
    <div className={styles.container}>
      <div className={styles.filters}>
        <select
          className={styles.select}
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
        >
          <option value="">All Status</option>
          <option value="resolved">Resolved</option>
          <option value="pending">Pending</option>
        </select>
        <select
          className={styles.select}
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
        >
          <option value={10}>10</option>
          <option value={20}>20</option>
          <option value={50}>50</option>
        </select>
        {isFetching && <span className={styles.refreshing}>updating...</span>}
      </div>

      {killmails.length === 0 ? (
        <div className={styles.empty}>No killmails</div>
      ) : (
        <div className={styles.list}>
          {killmails.map((km, i) => (
            <div key={`${km.killmailItemId}-${i}`} className={styles.row}>
              <span className={styles.timestamp}>
                {km.killTimestamp
                  ? new Date(km.killTimestamp).toLocaleString(undefined, {
                      month: "short",
                      day: "numeric",
                      hour: "2-digit",
                      minute: "2-digit",
                      second: "2-digit",
                    })
                  : "--"}
              </span>
              <span className={styles.killer}>{km.killer?.label ?? "Unknown"}</span>
              <span className={styles.vs}>destroyed</span>
              <span className={styles.victim}>{km.victim?.label ?? "Unknown"}</span>
              {km.status && (
                <span
                  className={`${styles.statusTag} ${
                    km.status === "resolved" ? styles.statusResolved : styles.statusPending
                  }`}
                >
                  {km.status}
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Verify frontend builds**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add frontend/src/panes/KillmailFeed.tsx frontend/src/panes/KillmailFeed.module.css
git commit -m "feat(frontend): add KillmailFeed pane"
```

---

### Task 6: BuildingLeaderboard Pane

**Files:**
- Create: `frontend/src/panes/BuildingLeaderboard.tsx`
- Create: `frontend/src/panes/BuildingLeaderboard.module.css`

- [ ] **Step 1: Create the CSS module**

Create `frontend/src/panes/BuildingLeaderboard.module.css`:

```css
.container { display: flex; flex-direction: column; gap: 8px; }
.filters { display: flex; gap: 6px; align-items: center; }
.select { padding: 3px 6px; font-size: 10px; font-family: var(--font-mono); background: var(--bg-deep); border: 1px solid var(--border); color: var(--text-primary); border-radius: 2px; }
.table { width: 100%; border-collapse: collapse; font-size: 10px; }
.table th { text-align: left; padding: 4px 6px; font-size: 9px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-muted); border-bottom: 1px solid var(--border); white-space: nowrap; }
.table td { padding: 4px 6px; color: var(--text-secondary); border-bottom: 1px solid var(--bg-header); }
.table tr:hover td { background: var(--bg-header); }
.rank { color: var(--hud-amber); font-weight: 600; text-align: center; width: 30px; }
.owner { font-size: 10px; }
.wallet { font-family: var(--font-mono); font-size: 9px; color: var(--text-muted); }
.count { color: var(--hud-amber); font-weight: 600; text-align: right; }
.unavailable { color: var(--status-error); font-size: 11px; padding: 8px; text-align: center; background: var(--bg-deep); border: 1px solid var(--status-error); border-radius: 2px; }
.empty { color: var(--text-muted); font-size: 11px; padding: 8px 0; }
.refreshing { font-size: 9px; color: var(--hud-amber); opacity: 0.6; }
```

- [ ] **Step 2: Create the component**

Create `frontend/src/panes/BuildingLeaderboard.tsx`:

```tsx
import { useState } from "react";
import { useBuildingLeaderboard } from "../hooks/useEveEyes";
import styles from "./BuildingLeaderboard.module.css";

const MODULE_TYPES = ["", "assembly", "gate", "network_node", "storage_unit", "turret"] as const;
const MODULE_LABELS: Record<string, string> = {
  "": "All Modules",
  assembly: "Assembly",
  gate: "Gate",
  network_node: "Network Node",
  storage_unit: "Storage Unit",
  turret: "Turret",
};

export function BuildingLeaderboard() {
  const [moduleName, setModuleName] = useState("");
  const [limit, setLimit] = useState(10);

  const { data, isError, isFetching } = useBuildingLeaderboard({
    limit,
    moduleName: moduleName || undefined,
  });

  if (isError) {
    return (
      <div className={styles.container}>
        <div className={styles.unavailable}>Intel Unavailable</div>
      </div>
    );
  }

  const entries = data?.leaderboard ?? [];

  return (
    <div className={styles.container}>
      <div className={styles.filters}>
        <select
          className={styles.select}
          value={moduleName}
          onChange={(e) => setModuleName(e.target.value)}
        >
          {MODULE_TYPES.map((m) => (
            <option key={m} value={m}>
              {MODULE_LABELS[m]}
            </option>
          ))}
        </select>
        <select
          className={styles.select}
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
        >
          <option value={10}>Top 10</option>
          <option value={25}>Top 25</option>
          <option value={50}>Top 50</option>
        </select>
        {isFetching && <span className={styles.refreshing}>updating...</span>}
      </div>

      {entries.length === 0 ? (
        <div className={styles.empty}>No leaderboard data</div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>#</th>
              <th>Owner</th>
              <th>Wallet</th>
              <th style={{ textAlign: "right" }}>Count</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((entry, i) => (
              <tr key={`${entry.wallet ?? ""}-${i}`}>
                <td className={styles.rank}>{i + 1}</td>
                <td className={styles.owner}>{entry.owner ?? "--"}</td>
                <td className={styles.wallet}>
                  {entry.wallet ? `${entry.wallet.slice(0, 8)}...${entry.wallet.slice(-4)}` : "--"}
                </td>
                <td className={styles.count}>{entry.count ?? 0}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Verify frontend builds**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add frontend/src/panes/BuildingLeaderboard.tsx frontend/src/panes/BuildingLeaderboard.module.css
git commit -m "feat(frontend): add BuildingLeaderboard pane"
```

---

### Task 7: TransactionExplorer Pane

**Files:**
- Create: `frontend/src/panes/TransactionExplorer.tsx`
- Create: `frontend/src/panes/TransactionExplorer.module.css`

- [ ] **Step 1: Create the CSS module**

Create `frontend/src/panes/TransactionExplorer.module.css`:

```css
.container { display: flex; flex-direction: column; gap: 8px; }
.filters { display: flex; gap: 6px; flex-wrap: wrap; }
.input { padding: 3px 6px; font-size: 10px; font-family: var(--font-mono); background: var(--bg-deep); border: 1px solid var(--border); color: var(--text-primary); border-radius: 2px; flex: 1; min-width: 120px; }
.input::placeholder { color: var(--text-muted); }
.select { padding: 3px 6px; font-size: 10px; font-family: var(--font-mono); background: var(--bg-deep); border: 1px solid var(--border); color: var(--text-primary); border-radius: 2px; }
.table { width: 100%; border-collapse: collapse; font-size: 10px; }
.table th { text-align: left; padding: 4px 6px; font-size: 9px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-muted); border-bottom: 1px solid var(--border); white-space: nowrap; }
.table td { padding: 4px 6px; color: var(--text-secondary); border-bottom: 1px solid var(--bg-header); }
.table tr:hover td { background: var(--bg-header); cursor: pointer; }
.digest { font-family: var(--font-mono); font-size: 10px; color: var(--hud-amber); }
.sender { font-family: var(--font-mono); font-size: 9px; }
.pagination { display: flex; gap: 8px; align-items: center; justify-content: center; font-size: 10px; }
.pageBtn { padding: 2px 8px; font-size: 10px; font-family: var(--font-mono); background: var(--bg-deep); border: 1px solid var(--border); color: var(--text-primary); border-radius: 2px; cursor: pointer; }
.pageBtn:hover { border-color: var(--hud-amber); }
.pageBtn:disabled { opacity: 0.3; cursor: default; }
.pageInfo { color: var(--text-muted); }
.expandedRow { background: var(--bg-header); }
.moveCallsPanel { padding: 6px 8px; font-size: 10px; }
.moveCallsTitle { font-size: 9px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-muted); margin-bottom: 4px; }
.moveCall { padding: 3px 0; border-bottom: 1px solid var(--border); display: flex; gap: 8px; align-items: baseline; }
.moveCall:last-child { border-bottom: none; }
.mcTarget { font-family: var(--font-mono); font-size: 9px; color: var(--hud-amber); }
.mcAction { font-size: 9px; color: var(--text-secondary); font-style: italic; }
.unavailable { color: var(--status-error); font-size: 11px; padding: 8px; text-align: center; background: var(--bg-deep); border: 1px solid var(--status-error); border-radius: 2px; }
.empty { color: var(--text-muted); font-size: 11px; padding: 8px 0; }
.loading { color: var(--text-muted); font-size: 10px; padding: 4px 0; }
```

- [ ] **Step 2: Create the component**

Create `frontend/src/panes/TransactionExplorer.tsx`:

```tsx
import { Fragment, useState } from "react";
import { useTransactionBlocks, useMoveCallsForTx } from "../hooks/useEveEyes";
import { StatusBadge } from "../components/StatusBadge";
import styles from "./TransactionExplorer.module.css";

function MoveCallsExpander({ digest }: { digest: string }) {
  const { data, isLoading, isError } = useMoveCallsForTx(digest);

  if (isLoading) return <div className={styles.loading}>Loading move calls...</div>;
  if (isError) return <div className={styles.loading}>Failed to load move calls</div>;

  const calls = data?.items ?? [];
  if (calls.length === 0) return <div className={styles.loading}>No move calls</div>;

  return (
    <div className={styles.moveCallsPanel}>
      <div className={styles.moveCallsTitle}>Move Calls ({calls.length})</div>
      {calls.map((mc, i) => (
        <div key={i} className={styles.moveCall}>
          <span className={styles.mcTarget}>
            {mc.moduleName ?? "?"}::{mc.functionName ?? "?"}
          </span>
          {mc.actionSummary && (
            <span className={styles.mcAction}>{mc.actionSummary}</span>
          )}
        </div>
      ))}
    </div>
  );
}

export function TransactionExplorer() {
  const [senderFilter, setSenderFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [digestSearch, setDigestSearch] = useState("");
  const [page, setPage] = useState(1);
  const [expandedDigest, setExpandedDigest] = useState<string | null>(null);

  const { data, isError, isFetching } = useTransactionBlocks({
    page,
    pageSize: 20,
    senderAddress: senderFilter || undefined,
    status: statusFilter || undefined,
    digest: digestSearch || undefined,
  });

  if (isError) {
    return (
      <div className={styles.container}>
        <div className={styles.unavailable}>Intel Unavailable</div>
      </div>
    );
  }

  const txs = data?.items ?? [];
  const hasMore = data?.pagination?.hasMore ?? txs.length === 20;

  return (
    <div className={styles.container}>
      <div className={styles.filters}>
        <input
          className={styles.input}
          placeholder="Sender address..."
          value={senderFilter}
          onChange={(e) => {
            setSenderFilter(e.target.value);
            setPage(1);
          }}
        />
        <input
          className={styles.input}
          placeholder="Digest..."
          value={digestSearch}
          onChange={(e) => {
            setDigestSearch(e.target.value);
            setPage(1);
          }}
        />
        <select
          className={styles.select}
          value={statusFilter}
          onChange={(e) => {
            setStatusFilter(e.target.value);
            setPage(1);
          }}
        >
          <option value="">All</option>
          <option value="success">Success</option>
          <option value="failure">Failure</option>
        </select>
      </div>

      {txs.length === 0 ? (
        <div className={styles.empty}>
          {isFetching ? "Loading..." : "No transactions"}
        </div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>Digest</th>
              <th>Sender</th>
              <th>Status</th>
              <th>Kind</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody>
            {txs.map((tx) => (
              <Fragment key={tx.digest}>
                <tr
                  onClick={() =>
                    setExpandedDigest(
                      expandedDigest === tx.digest ? null : tx.digest,
                    )
                  }
                >
                  <td className={styles.digest}>
                    {tx.digest?.slice(0, 12)}...
                  </td>
                  <td className={styles.sender}>
                    {tx.sender
                      ? `${tx.sender.slice(0, 8)}...${tx.sender.slice(-4)}`
                      : "--"}
                  </td>
                  <td>
                    <StatusBadge
                      label={tx.status ?? "unknown"}
                      variant={tx.status === "success" ? "ok" : "error"}
                    />
                  </td>
                  <td>{tx.transactionKind ?? "--"}</td>
                  <td>
                    {tx.transactionTime
                      ? new Date(tx.transactionTime).toLocaleString(undefined, {
                          month: "short",
                          day: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        })
                      : "--"}
                  </td>
                </tr>
                {expandedDigest === tx.digest && (
                  <tr className={styles.expandedRow}>
                    <td colSpan={5}>
                      <MoveCallsExpander digest={tx.digest} />
                    </td>
                  </tr>
                )}
              </Fragment>
            ))}
          </tbody>
        </table>
      )}

      <div className={styles.pagination}>
        <button
          className={styles.pageBtn}
          disabled={page <= 1}
          onClick={() => setPage((p) => p - 1)}
        >
          Prev
        </button>
        <span className={styles.pageInfo}>Page {page}</span>
        <button
          className={styles.pageBtn}
          disabled={!hasMore}
          onClick={() => setPage((p) => p + 1)}
        >
          Next
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Verify frontend builds**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add frontend/src/panes/TransactionExplorer.tsx frontend/src/panes/TransactionExplorer.module.css
git commit -m "feat(frontend): add TransactionExplorer pane with move call expansion"
```

---

### Task 8: Pane Registry + Final Build

**Files:**
- Modify: `frontend/src/config/paneRegistry.ts`

- [ ] **Step 1: Add imports and category type**

In `frontend/src/config/paneRegistry.ts`, add 3 imports after line 19 (LinkAssembly import):

```typescript
import { KillmailFeed } from "../panes/KillmailFeed";
import { BuildingLeaderboard } from "../panes/BuildingLeaderboard";
import { TransactionExplorer } from "../panes/TransactionExplorer";
```

Update the `category` type in the `PaneDefinition` interface from:

```typescript
  category: "dashboard" | "production" | "blueprint" | "orders" | "market" | "watcher" | "trigger" | "eve";
```

to:

```typescript
  category: "dashboard" | "production" | "blueprint" | "orders" | "market" | "watcher" | "trigger" | "eve" | "intel";
```

- [ ] **Step 2: Add 3 pane entries**

Add these 3 entries at the end of the `PANE_DEFS` array, before the closing `];`:

```typescript
  { id: "killmail-feed",        title: "Killmail Feed",        component: KillmailFeed,        defaultSize: { w: 8, h: 10 },  minSize: { w: 6, h: 6 },  category: "intel" },
  { id: "building-leaderboard", title: "Building Leaderboard", component: BuildingLeaderboard, defaultSize: { w: 8, h: 10 },  minSize: { w: 6, h: 6 },  category: "intel" },
  { id: "tx-explorer",          title: "Transaction Explorer",  component: TransactionExplorer,  defaultSize: { w: 12, h: 12 }, minSize: { w: 8, h: 8 },  category: "intel" },
```

- [ ] **Step 3: Verify typecheck**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 4: Verify production build**

Run: `cd frontend && npm run build`
Expected: build succeeds, outputs JS + CSS bundles

- [ ] **Step 5: Verify watcher typecheck**

Run: `cd watcher && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 6: Commit**

```bash
git add frontend/src/config/paneRegistry.ts
git commit -m "feat(frontend): register 3 intel panes (killmail, leaderboard, tx explorer)"
```

---

### Task 9: Smoke Test

- [ ] **Step 1: Verify Eve Eyes public endpoints are reachable**

Run the following curl commands and confirm they return JSON:

```bash
curl -s 'https://eve-eyes.d0v.xyz/api/indexer/killmails?limit=3' | head -c 200
curl -s 'https://eve-eyes.d0v.xyz/api/v1/indexer/building-leaderboard?limit=3' | head -c 200
curl -s 'https://eve-eyes.d0v.xyz/api/indexer/module-call-counts' | head -c 200
```

Expected: JSON responses (not 404 or error HTML)

- [ ] **Step 2: Verify proxy endpoint with API key**

```bash
curl -s 'https://eve-eyes.d0v.xyz/api/indexer/transaction-blocks?page=4&pageSize=5' \
  -H 'Authorization: ApiKey eve_ak_OGg2rSPof-S_13eN_kpDeIw4-rG5_q8leYZhdL2IV5w' | head -c 200
```

Expected: JSON with `items` array (not 401)

- [ ] **Step 3: Update progress.md**

Add to the completed section in `tasks/progress.md`:

```markdown
## Recently Completed (2026-04-01)

- [x] **Eve Eyes API Integration**
  - 3 new intel panes: KillmailFeed, BuildingLeaderboard, TransactionExplorer
  - Eve Eyes API client (`eveEyes.ts`) with public + proxy fetch pattern
  - 5 React Query hooks (`useEveEyes.ts`)
  - Watcher proxy: 2 routes with API key injection + query param whitelist
  - `intel` category added to pane registry (now 22 panes total)
  - Config: `VITE_EVE_EYES_URL` (frontend), `eve_eyes` section (watcher config)
```

- [ ] **Step 4: Commit progress update**

```bash
git add tasks/progress.md
git commit -m "docs: update progress with Eve Eyes API integration"
```

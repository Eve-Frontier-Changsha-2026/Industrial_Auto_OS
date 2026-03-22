# Industrial Auto OS — Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full EVE Frontier HUD-style React dashboard with 15 draggable/resizable panes for managing industrial production, work orders, marketplace, and watcher monitoring on SUI blockchain.

**Architecture:** Single-page React app with `react-grid-layout` for free-form pane management. All chain reads via `@tanstack/react-query` with polling. All writes via PTB builders + `@mysten/dapp-kit` signing. Watcher integration via REST API (added to existing watcher). CSS Modules for scoped HUD styling.

**Tech Stack:** React 18, Vite, TypeScript, react-grid-layout, @mysten/dapp-kit, @mysten/sui, @tanstack/react-query v5, recharts, CSS Modules

**Spec:** `docs/superpowers/specs/2026-03-21-frontend-design.md`

**Critical contract constraints (from spec review):**
- `start_production` only accepts `&BlueprintOriginal` — BPC path is `public(package)`, NOT PTB-callable
- Marketplace listing discovery via event query (no on-chain index)
- `delist_bpo`/`delist_bpc` return objects — PTB must `transferObjects` or TX aborts
- `TriggerRule` is owned object, query via `getOwnedObjects`
- `create_production_line`, `mint_bpo`, `destroy_empty_bpc` are CLI-only (not in frontend)

---

## File Structure

```
frontend/
├── index.html
├── vite.config.ts
├── tsconfig.json
├── package.json
├── .env.example                     # VITE_PKG_*, VITE_NETWORK, VITE_WATCHER_URL
├── public/
│   └── fonts/                       # JetBrains Mono woff2
├── src/
│   ├── main.tsx                     # ReactDOM.createRoot + providers
│   ├── App.tsx                      # TopBar + ResponsiveGridLayout + PaneManager
│   ├── App.module.css
│   ├── theme/
│   │   ├── variables.css            # CSS custom properties (amber palette)
│   │   ├── global.css               # Reset, scrollbar, base styles
│   │   └── panel.module.css         # Shared panel chrome styles
│   ├── components/
│   │   ├── TopBar.tsx               # Logo, wallet connect, network, [+ Add Panel]
│   │   ├── TopBar.module.css
│   │   ├── PaneChrome.tsx           # Reusable pane wrapper (titlebar, min/max/close)
│   │   ├── PaneChrome.module.css
│   │   ├── PaneMenu.tsx             # Dropdown listing available panes
│   │   ├── PaneMenu.module.css
│   │   ├── StatusBadge.tsx          # Colored status pill
│   │   └── StatusBadge.module.css
│   ├── panes/
│   │   ├── SystemOverview.tsx       # Summary stat cards
│   │   ├── SystemOverview.module.css
│   │   ├── ActivityFeed.tsx         # Real-time event log
│   │   ├── ActivityFeed.module.css
│   │   ├── ProductionMonitor.tsx    # Production lines + progress bars
│   │   ├── ProductionMonitor.module.css
│   │   ├── RecipeBrowser.tsx        # Recipe table + detail expand
│   │   ├── RecipeBrowser.module.css
│   │   ├── MaterialInventory.tsx    # Input/output buffer display
│   │   ├── MaterialInventory.module.css
│   │   ├── BlueprintInventory.tsx   # BPO/BPC list with ME/TE
│   │   ├── BlueprintInventory.module.css
│   │   ├── BlueprintMint.tsx        # Mint BPC form
│   │   ├── BlueprintMint.module.css
│   │   ├── WorkOrderBoard.tsx       # Order list + status filter
│   │   ├── WorkOrderBoard.module.css
│   │   ├── WorkOrderDetail.tsx      # Single order + actions
│   │   ├── WorkOrderDetail.module.css
│   │   ├── WorkOrderCreate.tsx      # Create order form
│   │   ├── WorkOrderCreate.module.css
│   │   ├── MarketListings.tsx       # BPO/BPC marketplace
│   │   ├── MarketListings.module.css
│   │   ├── LeaseManager.tsx         # Lease contracts
│   │   ├── LeaseManager.module.css
│   │   ├── WatcherStatus.tsx        # 11 rule handler status
│   │   ├── WatcherStatus.module.css
│   │   ├── TxLog.tsx                # Transaction history
│   │   ├── TxLog.module.css
│   │   ├── TriggerEngine.tsx        # Trigger rules + history
│   │   └── TriggerEngine.module.css
│   ├── hooks/
│   │   ├── useProductionLines.ts    # Query production line shared objects
│   │   ├── useRecipes.ts            # Query Recipe owned objects
│   │   ├── useBlueprints.ts         # Query BPO/BPC owned by wallet
│   │   ├── useWorkOrders.ts         # Query work order board
│   │   ├── useMarketplace.ts        # Query marketplace listings via events
│   │   ├── useLeases.ts             # Query lease agreements
│   │   ├── useTriggers.ts           # Query trigger rules (owned)
│   │   ├── useEvents.ts             # Query SUI events with cursor
│   │   ├── useWatcher.ts            # Fetch watcher REST API
│   │   ├── useLayout.ts             # Grid layout localStorage persistence
│   │   └── usePaneManager.ts        # Open/close/minimize/maximize pane state
│   ├── lib/
│   │   ├── ptb/
│   │   │   ├── production.ts        # start/complete, deposit materials/fuel, withdraw, operators
│   │   │   ├── blueprint.ts         # mint_bpc (handles returned object transfer)
│   │   │   ├── workOrder.ts         # create/accept/deliver/complete/auto-complete/cancel
│   │   │   ├── marketplace.ts       # list/buy/delist BPO/BPC (delist transfers returned object)
│   │   │   ├── lease.ts             # create/return/forfeit lease
│   │   │   └── triggerEngine.ts     # create/remove/toggle trigger rules
│   │   ├── constants.ts             # Package IDs, shared object IDs from env vars
│   │   ├── types.ts                 # TS types mirroring Move structs
│   │   ├── format.ts               # Format addresses, SUI amounts, timestamps
│   │   └── errors.ts               # Error code → human message mapping
│   └── config/
│       ├── defaultLayout.ts         # Default pane grid positions
│       └── paneRegistry.ts          # PaneDefinition registry
├── tests/
│   ├── lib/
│   │   ├── format.test.ts
│   │   ├── errors.test.ts
│   │   ├── ptb/
│   │   │   ├── production.test.ts
│   │   │   ├── blueprint.test.ts
│   │   │   ├── workOrder.test.ts
│   │   │   ├── marketplace.test.ts
│   │   │   ├── lease.test.ts
│   │   │   └── triggerEngine.test.ts
│   │   └── constants.test.ts
│   └── hooks/
│       ├── useLayout.test.ts
│       └── usePaneManager.test.ts
```

Watcher addition (existing `watcher/` directory):
```
watcher/src/
├── api/
│   ├── server.ts                    # Express app: /status, /tx-log, /health
│   └── server.test.ts
├── index.ts                         # Modified: start HTTP server alongside main loop
```

---

## Phase 0: Watcher REST API

### Task 1: Add Express REST API to Watcher

**Files:**
- Create: `watcher/src/api/server.ts`
- Modify: `watcher/src/index.ts`
- Modify: `watcher/package.json`
- Create: `watcher/tests/api/server.test.ts`

**Context:**
- Watcher currently runs as CLI-only (no HTTP). Need 3 endpoints for frontend WatcherStatus + TxLog panes.
- SQLite DB already has `tx_log` table. Rule registry already has `listAll()`.
- Watcher uses ESM (`"type": "module"` in package.json).

- [ ] **Step 1: Install express + types**

```bash
cd watcher && npm install express && npm install -D @types/express
```

- [ ] **Step 2: Write failing tests for API endpoints**

Create `watcher/tests/api/server.test.ts`:
```typescript
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import express from "express";
import { createApiRouter } from "../../src/api/server.js";
import type { Database } from "better-sqlite3";
import { createDb } from "../../src/db/sqlite.js";

describe("Watcher REST API", () => {
  let db: Database;
  let app: express.Express;

  beforeAll(() => {
    db = createDb(":memory:");
    // Insert test data
    db.prepare(
      "INSERT INTO tx_log (rule_name, tx_digest, status, gas_used, created_at) VALUES (?, ?, ?, ?, ?)"
    ).run("production_completer", "0xABC123", "success", 1500000, Date.now());
    db.prepare(
      "INSERT INTO tx_log (rule_name, tx_digest, status, error, gas_used, created_at) VALUES (?, ?, ?, ?, ?, ?)"
    ).run("order_acceptor", "0xDEF456", "fail", "InsufficientGas", 0, Date.now());

    const mockRegistry = {
      listAll: () => [
        { name: "production_completer", description: "Complete finished jobs", enabled: true },
        { name: "order_acceptor", description: "Accept work orders", enabled: false },
      ],
    };

    app = express();
    app.use("/", createApiRouter(db, mockRegistry as any));
  });

  afterAll(() => db.close());

  it("GET /health returns uptime and version", async () => {
    const res = await requestApp(app, "/health");
    expect(res.status).toBe(200);
    const body = JSON.parse(res.body);
    expect(body).toHaveProperty("uptime_ms");
    expect(body).toHaveProperty("last_poll");
    expect(body.status).toBe("ok");
  });

  it("GET /status returns rule handler states", async () => {
    const res = await requestApp(app, "/status");
    expect(res.status).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.rules).toHaveLength(2);
    expect(body.rules[0].name).toBe("production_completer");
    expect(body.rules[0].enabled).toBe(true);
  });

  it("GET /tx-log returns recent transactions", async () => {
    const res = await requestApp(app, "/tx-log");
    expect(res.status).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.transactions).toHaveLength(2);
    expect(body.transactions[0].tx_digest).toBe("0xDEF456"); // newest first
  });

  it("GET /tx-log?limit=1 respects limit", async () => {
    const res = await requestApp(app, "/tx-log?limit=1");
    const body = JSON.parse(res.body);
    expect(body.transactions).toHaveLength(1);
  });

  it("GET /tx-log?status=fail filters by status", async () => {
    const res = await requestApp(app, "/tx-log?status=fail");
    const body = JSON.parse(res.body);
    expect(body.transactions).toHaveLength(1);
    expect(body.transactions[0].status).toBe("fail");
  });
});

// Helper: make request to express app without starting server
async function requestApp(app: express.Express, path: string): Promise<{ status: number; body: string }> {
  return new Promise((resolve) => {
    const http = await import("node:http");
    const server = http.createServer(app);
    server.listen(0, () => {
      const port = (server.address() as any).port;
      http.get(`http://localhost:${port}${path}`, (res: any) => {
        let body = "";
        res.on("data", (chunk: string) => (body += chunk));
        res.on("end", () => {
          server.close();
          resolve({ status: res.statusCode, body });
        });
      });
    });
  });
}
```

- [ ] **Step 3: Run tests, verify they fail**

```bash
cd watcher && npx vitest run tests/api/server.test.ts
```

Expected: FAIL — `createApiRouter` not found.

- [ ] **Step 4: Implement API router**

Create `watcher/src/api/server.ts`:
```typescript
import { Router } from "express";
import type { Database } from "better-sqlite3";
import type { RuleRegistry } from "../rules/registry.js";

const startTime = Date.now();
let lastPollTimestamp = Date.now();

export function updateLastPoll(): void {
  lastPollTimestamp = Date.now();
}

export function createApiRouter(db: Database, registry: RuleRegistry): Router {
  const router = Router();

  router.get("/health", (_req, res) => {
    res.json({
      status: "ok",
      uptime_ms: Date.now() - startTime,
      last_poll: lastPollTimestamp,
    });
  });

  router.get("/status", (_req, res) => {
    const rules = registry.listAll().map((r) => ({
      name: r.name,
      description: r.description,
      enabled: r.enabled,
    }));
    res.json({ rules });
  });

  router.get("/tx-log", (req, res) => {
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const status = req.query.status as string | undefined;
    const ruleName = req.query.rule as string | undefined;

    let sql = "SELECT * FROM tx_log";
    const params: any[] = [];
    const conditions: string[] = [];

    if (status) {
      conditions.push("status = ?");
      params.push(status);
    }
    if (ruleName) {
      conditions.push("rule_name = ?");
      params.push(ruleName);
    }

    if (conditions.length) sql += " WHERE " + conditions.join(" AND ");
    sql += " ORDER BY created_at DESC LIMIT ?";
    params.push(limit);

    const transactions = db.prepare(sql).all(...params);
    res.json({ transactions, total: transactions.length });
  });

  return router;
}
```

- [ ] **Step 5: Run tests, verify they pass**

```bash
cd watcher && npx vitest run tests/api/server.test.ts
```

- [ ] **Step 6: Integrate API server into watcher index.ts**

Modify `watcher/src/index.ts` — add after engine setup, before main loop:
```typescript
import express from "express";
import { createApiRouter, updateLastPoll } from "./api/server.js";

// ... after engine setup ...

// ─── REST API ────────────────────────────────
const apiApp = express();
apiApp.use((_req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  next();
});
apiApp.use("/", createApiRouter(db, registry));
const apiPort = config.api?.port ?? 3001;
apiApp.listen(apiPort, () => {
  console.log(`API server on http://localhost:${apiPort}`);
});
```

Add `updateLastPoll()` call at the top of the poll loop body.

- [ ] **Step 7: Add `api.port` to config schema**

Modify `watcher/src/config.ts` — add optional `api?: { port?: number }` field to WatcherConfig type.

- [ ] **Step 8: Run all watcher tests, verify nothing broke**

```bash
cd watcher && npx vitest run
```

- [ ] **Step 9: Commit**

```bash
git add watcher/src/api/ watcher/tests/api/ watcher/src/index.ts watcher/src/config.ts watcher/package.json watcher/package-lock.json
git commit -m "feat(watcher): add REST API endpoints for frontend integration"
```

---

## Phase 1: Frontend Project Scaffold

### Task 2: Initialize Vite + React + TypeScript Project

**Files:**
- Create: `frontend/package.json`
- Create: `frontend/vite.config.ts`
- Create: `frontend/tsconfig.json`
- Create: `frontend/index.html`
- Create: `frontend/.env.example`
- Create: `frontend/src/main.tsx`

**Context:**
- Use `npm create vite@latest` or manual setup. Target React 18 with TypeScript.
- @mysten/dapp-kit requires `@mysten/sui` as peer dependency.
- Must set `define: { global: "globalThis" }` in vite config for SUI SDK compatibility.

- [ ] **Step 1: Create Vite project manually**

```bash
mkdir -p frontend/src frontend/public/fonts
```

Create `frontend/package.json`:
```json
{
  "name": "industrial-auto-os-frontend",
  "private": true,
  "version": "0.0.1",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest",
    "typecheck": "tsc --noEmit"
  }
}
```

- [ ] **Step 2: Install dependencies**

```bash
cd frontend && npm install react react-dom @mysten/dapp-kit @mysten/sui @tanstack/react-query react-grid-layout recharts
npm install -D typescript @types/react @types/react-dom @vitejs/plugin-react vite vitest @testing-library/react @testing-library/jest-dom jsdom @types/react-grid-layout
```

- [ ] **Step 3: Create config files**

Create `frontend/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noFallthroughCasesInSwitch": true,
    "forceConsistentCasingInFileNames": true,
    "types": ["vitest/globals"]
  },
  "include": ["src", "tests"]
}
```

Create `frontend/vite.config.ts`:
```typescript
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  define: { global: "globalThis" },
  css: { modules: { localsConvention: "camelCase" } },
  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: [],
  },
});
```

Create `frontend/.env.example`:
```
VITE_NETWORK=testnet
VITE_PKG_INDUSTRIAL_CORE=0x...
VITE_PKG_WORK_ORDER=0x...
VITE_PKG_MARKETPLACE=0x...
VITE_WORK_ORDER_BOARD=0x...
VITE_MARKETPLACE=0x...
VITE_WATCHER_URL=http://localhost:3001
VITE_PRODUCTION_LINE_IDS=0x...
VITE_RECIPE_IDS=0x...,0x...
```

- [ ] **Step 4: Create entry files**

Create `frontend/index.html`:
```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Industrial Auto OS</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

Create `frontend/src/main.tsx`:
```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { createNetworkConfig, SuiClientProvider, WalletProvider } from "@mysten/dapp-kit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { getFullnodeUrl } from "@mysten/sui/client";
import "@mysten/dapp-kit/dist/index.css";
import "./theme/variables.css";
import "./theme/global.css";
import App from "./App";

const { networkConfig } = createNetworkConfig({
  testnet: { url: getFullnodeUrl("testnet") },
  mainnet: { url: getFullnodeUrl("mainnet") },
});

const queryClient = new QueryClient({
  defaultOptions: { queries: { refetchOnWindowFocus: false } },
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <SuiClientProvider networks={networkConfig} defaultNetwork="testnet">
        <WalletProvider autoConnect>
          <App />
        </WalletProvider>
      </SuiClientProvider>
    </QueryClientProvider>
  </StrictMode>
);
```

Create `frontend/src/App.tsx` (placeholder):
```tsx
export default function App() {
  return <div>Industrial Auto OS</div>;
}
```

- [ ] **Step 5: Verify dev server starts**

```bash
cd frontend && npm run dev -- --host 0.0.0.0
```

Open browser, confirm "Industrial Auto OS" renders. Kill server.

- [ ] **Step 6: Verify typecheck passes**

```bash
cd frontend && npx tsc --noEmit
```

- [ ] **Step 7: Commit**

```bash
git add frontend/
git commit -m "feat(frontend): scaffold Vite + React + SUI dApp Kit project"
```

---

### Task 3: EVE Frontier HUD Theme (CSS)

**Files:**
- Create: `frontend/src/theme/variables.css`
- Create: `frontend/src/theme/global.css`
- Create: `frontend/src/theme/panel.module.css`

**Context:**
- Amber Industrial palette from spec section 2. Monospace typography.
- All colors as CSS custom properties for consistency.
- Panel chrome shared across all 15 panes.

- [ ] **Step 1: Create CSS variables**

Create `frontend/src/theme/variables.css`:
```css
:root {
  --bg-deep: #0c0a04;
  --bg-panel: #110e04;
  --bg-header: #1a1408;
  --border: #3a2d0a;
  --text-primary: #e8d088;
  --text-secondary: #b89a40;
  --text-muted: #8a7530;
  --accent: #c9a84c;
  --status-ok: #4caf50;
  --status-warn: #e8a82d;
  --status-error: #c94040;
  --status-info: #5b8fb9;
  --progress-fill: linear-gradient(90deg, #8a6b10, #c9a84c);
  --font-mono: "JetBrains Mono", "Fira Code", monospace;
  --topbar-height: 36px;
}
```

- [ ] **Step 2: Create global reset styles**

Create `frontend/src/theme/global.css`:
```css
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

html, body, #root {
  height: 100%;
  background: var(--bg-deep);
  color: var(--text-primary);
  font-family: var(--font-mono);
  font-size: 13px;
  line-height: 1.4;
  overflow: hidden;
}

::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: var(--bg-deep); }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }

input, select, textarea, button {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-primary);
  background: var(--bg-deep);
  border: 1px solid var(--border);
  border-radius: 2px;
  padding: 4px 8px;
  outline: none;
}

input:focus, select:focus, textarea:focus {
  border-color: var(--accent);
}

button {
  cursor: pointer;
  background: var(--bg-header);
  border: 1px solid var(--border);
  padding: 4px 12px;
  text-transform: uppercase;
  font-size: 10px;
  letter-spacing: 1px;
  color: var(--text-secondary);
  transition: background 0.15s, border-color 0.15s;
}
button:hover { background: var(--border); border-color: var(--accent); color: var(--text-primary); }
button:disabled { opacity: 0.4; cursor: not-allowed; }
```

- [ ] **Step 3: Create shared panel chrome CSS module**

Create `frontend/src/theme/panel.module.css`:
```css
.panel {
  background: var(--bg-panel);
  border: 1px solid var(--border);
  border-radius: 2px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  height: 100%;
}

.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: var(--bg-header);
  border-bottom: 1px solid var(--border);
  padding: 0 8px;
  height: 28px;
  min-height: 28px;
  cursor: grab;
  user-select: none;
}

.title {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 2px;
  color: var(--accent);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.controls {
  display: flex;
  gap: 4px;
  flex-shrink: 0;
}

.controlBtn {
  background: none;
  border: none;
  color: var(--text-muted);
  font-size: 12px;
  padding: 0 4px;
  cursor: pointer;
  line-height: 1;
  text-transform: none;
  letter-spacing: 0;
}
.controlBtn:hover { color: var(--text-primary); background: none; border: none; }

.body {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
}

.minimized .body { display: none; }
.minimized { height: 28px !important; min-height: 28px; }
```

- [ ] **Step 4: Verify build still works**

```bash
cd frontend && npx tsc --noEmit && npx vite build
```

- [ ] **Step 5: Commit**

```bash
git add frontend/src/theme/
git commit -m "feat(frontend): add EVE Frontier amber HUD theme"
```

---

## Phase 2: Core Shell Components

### Task 4: PaneChrome + StatusBadge Components

**Files:**
- Create: `frontend/src/components/PaneChrome.tsx`
- Create: `frontend/src/components/PaneChrome.module.css`
- Create: `frontend/src/components/StatusBadge.tsx`
- Create: `frontend/src/components/StatusBadge.module.css`

**Context:**
- PaneChrome wraps every pane with title bar + minimize/maximize/close buttons.
- It receives `title`, `onClose`, `onMinimize`, `onMaximize`, `minimized` props.
- StatusBadge renders a colored pill with status text.

- [ ] **Step 1: Create PaneChrome component**

```tsx
// frontend/src/components/PaneChrome.tsx
import { type ReactNode } from "react";
import styles from "./PaneChrome.module.css";

interface Props {
  title: string;
  minimized?: boolean;
  onMinimize?: () => void;
  onMaximize?: () => void;
  onClose?: () => void;
  children: ReactNode;
}

export function PaneChrome({ title, minimized, onMinimize, onMaximize, onClose, children }: Props) {
  return (
    <div className={`${styles.panel} ${minimized ? styles.minimized : ""}`}>
      <div className={styles.header}>
        <span className={styles.title}>{title}</span>
        <div className={styles.controls}>
          {onMinimize && (
            <button className={styles.controlBtn} onClick={onMinimize} title="Minimize">_</button>
          )}
          {onMaximize && (
            <button className={styles.controlBtn} onClick={onMaximize} title="Maximize">□</button>
          )}
          {onClose && (
            <button className={styles.controlBtn} onClick={onClose} title="Close">×</button>
          )}
        </div>
      </div>
      <div className={styles.body}>{children}</div>
    </div>
  );
}
```

Use `panel.module.css` from theme as `PaneChrome.module.css` (copy/symlink or import directly).

- [ ] **Step 2: Create StatusBadge component**

```tsx
// frontend/src/components/StatusBadge.tsx
import styles from "./StatusBadge.module.css";

type Variant = "ok" | "warn" | "error" | "info" | "muted";

interface Props {
  label: string;
  variant?: Variant;
}

export function StatusBadge({ label, variant = "muted" }: Props) {
  return <span className={`${styles.badge} ${styles[variant]}`}>{label}</span>;
}
```

```css
/* frontend/src/components/StatusBadge.module.css */
.badge {
  display: inline-block;
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 1px;
  padding: 2px 6px;
  border-radius: 2px;
  border: 1px solid;
}
.ok    { color: var(--status-ok);   border-color: var(--status-ok);   background: rgba(76,175,80,0.1); }
.warn  { color: var(--status-warn); border-color: var(--status-warn); background: rgba(232,168,45,0.1); }
.error { color: var(--status-error);border-color: var(--status-error);background: rgba(201,64,64,0.1); }
.info  { color: var(--status-info); border-color: var(--status-info); background: rgba(91,143,185,0.1); }
.muted { color: var(--text-muted);  border-color: var(--border);      background: transparent; }
```

- [ ] **Step 3: Typecheck**

```bash
cd frontend && npx tsc --noEmit
```

- [ ] **Step 4: Commit**

```bash
git add frontend/src/components/
git commit -m "feat(frontend): add PaneChrome and StatusBadge components"
```

---

### Task 5: Pane Registry + Layout Hooks + PaneMenu

**Files:**
- Create: `frontend/src/config/paneRegistry.ts`
- Create: `frontend/src/config/defaultLayout.ts`
- Create: `frontend/src/hooks/useLayout.ts`
- Create: `frontend/src/hooks/usePaneManager.ts`
- Create: `frontend/src/components/PaneMenu.tsx`
- Create: `frontend/src/components/PaneMenu.module.css`
- Create: `frontend/tests/hooks/useLayout.test.ts`
- Create: `frontend/tests/hooks/usePaneManager.test.ts`

**Context:**
- PaneRegistry maps pane IDs to components + metadata. All 15 panes registered here.
- useLayout manages react-grid-layout state + localStorage persistence.
- usePaneManager tracks which panes are open/minimized/maximized.
- PaneMenu is the [+ Add Panel] dropdown.

- [ ] **Step 1: Write tests for useLayout (localStorage persistence)**

```typescript
// frontend/tests/hooks/useLayout.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { saveLayout, loadLayout, STORAGE_KEY } from "../../src/hooks/useLayout";
import type { Layout } from "react-grid-layout";

describe("useLayout persistence", () => {
  beforeEach(() => localStorage.clear());

  it("returns null when no saved layout", () => {
    expect(loadLayout()).toBeNull();
  });

  it("round-trips layout to localStorage", () => {
    const layout: Layout[] = [{ i: "system-overview", x: 0, y: 0, w: 6, h: 4 }];
    saveLayout(layout);
    expect(loadLayout()).toEqual(layout);
  });

  it("returns null for corrupted data", () => {
    localStorage.setItem(STORAGE_KEY, "not-json");
    expect(loadLayout()).toBeNull();
  });
});
```

- [ ] **Step 2: Write tests for usePaneManager**

```typescript
// frontend/tests/hooks/usePaneManager.test.ts
import { describe, it, expect } from "vitest";
import { getDefaultPanes, addPane, removePane, toggleMinimize } from "../../src/hooks/usePaneManager";

describe("usePaneManager", () => {
  it("returns default pane set", () => {
    const panes = getDefaultPanes();
    expect(panes).toContain("system-overview");
    expect(panes).toContain("production-monitor");
    expect(panes).toContain("activity-feed");
  });

  it("addPane adds pane ID to set", () => {
    const panes = new Set(["a"]);
    expect(addPane(panes, "b")).toEqual(new Set(["a", "b"]));
  });

  it("removePane removes pane ID", () => {
    const panes = new Set(["a", "b"]);
    expect(removePane(panes, "a")).toEqual(new Set(["b"]));
  });

  it("toggleMinimize flips state", () => {
    const mins = new Set<string>();
    expect(toggleMinimize(mins, "a")).toEqual(new Set(["a"]));
    expect(toggleMinimize(new Set(["a"]), "a")).toEqual(new Set());
  });
});
```

- [ ] **Step 3: Run tests, verify fail**

```bash
cd frontend && npx vitest run tests/hooks/
```

- [ ] **Step 4: Implement pane registry**

Create `frontend/src/config/paneRegistry.ts`:
```typescript
import type { ComponentType } from "react";

export interface PaneDefinition {
  id: string;
  title: string;
  component: ComponentType;
  defaultSize: { w: number; h: number };
  minSize: { w: number; h: number };
  category: "dashboard" | "production" | "blueprint" | "orders" | "market" | "watcher" | "trigger";
}

// Lazy-loaded pane components — filled in by Task 6+ as panes are built.
// Placeholder until real components exist.
const Placeholder = () => null;

export const PANE_DEFS: PaneDefinition[] = [
  { id: "system-overview",     title: "System Overview",      component: Placeholder, defaultSize: { w: 24, h: 4 },  minSize: { w: 8, h: 3 },  category: "dashboard" },
  { id: "activity-feed",       title: "Activity Feed",        component: Placeholder, defaultSize: { w: 8, h: 10 },  minSize: { w: 6, h: 4 },  category: "dashboard" },
  { id: "production-monitor",  title: "Production Monitor",   component: Placeholder, defaultSize: { w: 10, h: 10 }, minSize: { w: 8, h: 6 },  category: "production" },
  { id: "recipe-browser",      title: "Recipe Browser",       component: Placeholder, defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "production" },
  { id: "material-inventory",  title: "Material Inventory",   component: Placeholder, defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "production" },
  { id: "blueprint-inventory", title: "Blueprint Inventory",  component: Placeholder, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 4 },  category: "blueprint" },
  { id: "blueprint-mint",      title: "Blueprint Mint",       component: Placeholder, defaultSize: { w: 6, h: 6 },   minSize: { w: 5, h: 4 },  category: "blueprint" },
  { id: "work-order-board",    title: "Work Order Board",     component: Placeholder, defaultSize: { w: 12, h: 10 }, minSize: { w: 8, h: 6 },  category: "orders" },
  { id: "work-order-detail",   title: "Work Order Detail",    component: Placeholder, defaultSize: { w: 8, h: 10 },  minSize: { w: 6, h: 6 },  category: "orders" },
  { id: "work-order-create",   title: "Work Order Create",    component: Placeholder, defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 6 },  category: "orders" },
  { id: "market-listings",     title: "Market Listings",      component: Placeholder, defaultSize: { w: 12, h: 10 }, minSize: { w: 8, h: 6 },  category: "market" },
  { id: "lease-manager",       title: "Lease Manager",        component: Placeholder, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 5 },  category: "market" },
  { id: "watcher-status",      title: "Watcher Status",       component: Placeholder, defaultSize: { w: 8, h: 8 },   minSize: { w: 6, h: 4 },  category: "watcher" },
  { id: "tx-log",              title: "TX Log",               component: Placeholder, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 4 },  category: "watcher" },
  { id: "trigger-engine",      title: "Trigger Engine",       component: Placeholder, defaultSize: { w: 10, h: 8 },  minSize: { w: 8, h: 5 },  category: "trigger" },
];

export const PANE_MAP = new Map(PANE_DEFS.map((d) => [d.id, d]));
```

- [ ] **Step 5: Implement default layout**

Create `frontend/src/config/defaultLayout.ts`:
```typescript
import type { Layout } from "react-grid-layout";

export const DEFAULT_LAYOUT: Layout[] = [
  { i: "system-overview",    x: 0,  y: 0,  w: 24, h: 4 },
  { i: "production-monitor", x: 0,  y: 4,  w: 10, h: 10 },
  { i: "work-order-board",   x: 10, y: 4,  w: 8,  h: 10 },
  { i: "activity-feed",      x: 18, y: 4,  w: 6,  h: 10 },
  { i: "trigger-engine",     x: 0,  y: 14, w: 10, h: 8 },
];

export const DEFAULT_OPEN_PANES = DEFAULT_LAYOUT.map((l) => l.i);
```

- [ ] **Step 6: Implement useLayout and usePaneManager**

Create `frontend/src/hooks/useLayout.ts`:
```typescript
import { useState, useCallback } from "react";
import type { Layout } from "react-grid-layout";
import { DEFAULT_LAYOUT } from "../config/defaultLayout";

export const STORAGE_KEY = "industrial-auto-os-layout";

export function saveLayout(layout: Layout[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(layout));
}

export function loadLayout(): Layout[] | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as Layout[];
  } catch {
    return null;
  }
}

export function useLayout() {
  const [layout, setLayout] = useState<Layout[]>(() => loadLayout() ?? DEFAULT_LAYOUT);

  const onLayoutChange = useCallback((newLayout: Layout[]) => {
    setLayout(newLayout);
    saveLayout(newLayout);
  }, []);

  return { layout, onLayoutChange };
}
```

Create `frontend/src/hooks/usePaneManager.ts`:
```typescript
import { useState, useCallback } from "react";
import { DEFAULT_OPEN_PANES } from "../config/defaultLayout";
import { PANE_MAP } from "../config/paneRegistry";

export function getDefaultPanes(): string[] {
  return [...DEFAULT_OPEN_PANES];
}

export function addPane(panes: Set<string>, id: string): Set<string> {
  return new Set([...panes, id]);
}

export function removePane(panes: Set<string>, id: string): Set<string> {
  const next = new Set(panes);
  next.delete(id);
  return next;
}

export function toggleMinimize(minimized: Set<string>, id: string): Set<string> {
  const next = new Set(minimized);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  return next;
}

export function usePaneManager() {
  const [openPanes, setOpenPanes] = useState<Set<string>>(() => new Set(DEFAULT_OPEN_PANES));
  const [minimized, setMinimized] = useState<Set<string>>(new Set());
  const [maximized, setMaximized] = useState<string | null>(null);

  const open = useCallback((id: string) => setOpenPanes((p) => addPane(p, id)), []);
  const close = useCallback((id: string) => {
    setOpenPanes((p) => removePane(p, id));
    setMinimized((m) => { const n = new Set(m); n.delete(id); return n; });
    if (maximized === id) setMaximized(null);
  }, [maximized]);
  const minimize = useCallback((id: string) => setMinimized((m) => toggleMinimize(m, id)), []);
  const maximize = useCallback((id: string) => setMaximized((prev) => (prev === id ? null : id)), []);

  return { openPanes, minimized, maximized, open, close, minimize, maximize };
}
```

- [ ] **Step 7: Implement PaneMenu**

Create `frontend/src/components/PaneMenu.tsx`:
```tsx
import { useState, useRef, useEffect } from "react";
import { PANE_DEFS } from "../config/paneRegistry";
import styles from "./PaneMenu.module.css";

interface Props {
  openPanes: Set<string>;
  onAdd: (id: string) => void;
}

export function PaneMenu({ openPanes, onAdd }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const categories = [...new Set(PANE_DEFS.map((d) => d.category))];

  return (
    <div className={styles.wrapper} ref={ref}>
      <button className={styles.trigger} onClick={() => setOpen(!open)}>+ ADD PANEL</button>
      {open && (
        <div className={styles.dropdown}>
          {categories.map((cat) => (
            <div key={cat}>
              <div className={styles.catLabel}>{cat}</div>
              {PANE_DEFS.filter((d) => d.category === cat).map((d) => (
                <button
                  key={d.id}
                  className={styles.item}
                  disabled={openPanes.has(d.id)}
                  onClick={() => { onAdd(d.id); setOpen(false); }}
                >
                  {d.title} {openPanes.has(d.id) && "✓"}
                </button>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

Create `frontend/src/components/PaneMenu.module.css`:
```css
.wrapper { position: relative; }
.trigger { font-size: 10px; letter-spacing: 1px; }
.dropdown {
  position: absolute; top: 100%; left: 0; z-index: 100;
  background: var(--bg-panel); border: 1px solid var(--border);
  min-width: 200px; max-height: 400px; overflow-y: auto;
  padding: 4px 0;
}
.catLabel {
  font-size: 9px; text-transform: uppercase; letter-spacing: 1px;
  color: var(--text-muted); padding: 6px 12px 2px;
}
.item {
  display: block; width: 100%; text-align: left;
  padding: 4px 12px; font-size: 11px; border: none;
  background: none; text-transform: none; letter-spacing: 0;
}
.item:hover:not(:disabled) { background: var(--bg-header); }
.item:disabled { color: var(--text-muted); }
```

- [ ] **Step 8: Run tests, verify pass**

```bash
cd frontend && npx vitest run
```

- [ ] **Step 9: Commit**

```bash
git add frontend/src/config/ frontend/src/hooks/ frontend/src/components/PaneMenu* frontend/tests/
git commit -m "feat(frontend): add pane registry, layout persistence, and pane manager"
```

---

### Task 6: TopBar + App Shell with GridLayout

**Files:**
- Create: `frontend/src/components/TopBar.tsx`
- Create: `frontend/src/components/TopBar.module.css`
- Modify: `frontend/src/App.tsx` (full rewrite — currently placeholder)
- Create: `frontend/src/App.module.css`

**Context:**
- TopBar: logo + PaneMenu + network indicator + wallet ConnectButton.
- App: wires TopBar + ResponsiveGridLayout + PaneChrome for each open pane.
- react-grid-layout needs `react-grid-layout/css/styles.css` and `react-resizable/css/styles.css` imported.

- [ ] **Step 1: Create TopBar**

```tsx
// frontend/src/components/TopBar.tsx
import { ConnectButton, useCurrentAccount } from "@mysten/dapp-kit";
import { PaneMenu } from "./PaneMenu";
import styles from "./TopBar.module.css";

interface Props {
  openPanes: Set<string>;
  onAddPane: (id: string) => void;
}

export function TopBar({ openPanes, onAddPane }: Props) {
  const account = useCurrentAccount();
  const network = import.meta.env.VITE_NETWORK ?? "testnet";

  return (
    <header className={styles.bar}>
      <div className={styles.logo}>⬡ INDUSTRIAL AUTO OS</div>
      <PaneMenu openPanes={openPanes} onAdd={onAddPane} />
      <div className={styles.right}>
        <span className={styles.network}>{network}</span>
        <ConnectButton />
      </div>
    </header>
  );
}
```

```css
/* frontend/src/components/TopBar.module.css */
.bar {
  display: flex; align-items: center; justify-content: space-between;
  height: var(--topbar-height); padding: 0 12px;
  background: var(--bg-header); border-bottom: 1px solid var(--border);
  gap: 12px;
}
.logo {
  font-size: 12px; font-weight: 700; letter-spacing: 2px;
  color: var(--accent); white-space: nowrap;
}
.right { display: flex; align-items: center; gap: 12px; }
.network {
  font-size: 10px; text-transform: uppercase; letter-spacing: 1px;
  color: var(--status-ok); border: 1px solid var(--status-ok);
  padding: 2px 6px; border-radius: 2px;
}
```

- [ ] **Step 2: Implement App with GridLayout**

```tsx
// frontend/src/App.tsx
import { Responsive, WidthProvider } from "react-grid-layout";
import "react-grid-layout/css/styles.css";
import "react-resizable/css/styles.css";
import { TopBar } from "./components/TopBar";
import { PaneChrome } from "./components/PaneChrome";
import { PANE_MAP } from "./config/paneRegistry";
import { useLayout } from "./hooks/useLayout";
import { usePaneManager } from "./hooks/usePaneManager";
import styles from "./App.module.css";

const ResponsiveGrid = WidthProvider(Responsive);

export default function App() {
  const { layout, onLayoutChange } = useLayout();
  const { openPanes, minimized, maximized, open, close, minimize, maximize } = usePaneManager();

  const visibleLayout = layout.filter((l) => openPanes.has(l.i));

  return (
    <div className={styles.app}>
      <TopBar openPanes={openPanes} onAddPane={open} />
      <div className={styles.grid}>
        <ResponsiveGrid
          className={styles.gridInner}
          layouts={{ lg: visibleLayout }}
          breakpoints={{ xl: 1600, lg: 1200, md: 996 }}
          cols={{ xl: 24, lg: 24, md: 24 }}
          rowHeight={30}
          margin={[4, 4]}
          onLayoutChange={(newLayout) => onLayoutChange(newLayout)}
          draggableHandle="[data-drag-handle]"
          compactType="vertical"
          isResizable
          isDraggable
        >
          {[...openPanes].map((paneId) => {
            const def = PANE_MAP.get(paneId);
            if (!def) return null;
            const Comp = def.component;
            const isMinimized = minimized.has(paneId);

            if (maximized === paneId) return null; // rendered separately as overlay

            return (
              <div key={paneId}>
                <PaneChrome
                  title={def.title}
                  minimized={isMinimized}
                  onMinimize={() => minimize(paneId)}
                  onMaximize={() => maximize(paneId)}
                  onClose={() => close(paneId)}
                >
                  <Comp />
                </PaneChrome>
              </div>
            );
          })}
        </ResponsiveGrid>

        {/* Maximized pane overlay */}
        {maximized && PANE_MAP.has(maximized) && (() => {
          const def = PANE_MAP.get(maximized)!;
          const Comp = def.component;
          return (
            <div className={styles.overlay}>
              <PaneChrome
                title={def.title}
                onMaximize={() => maximize(maximized)}
                onClose={() => close(maximized)}
              >
                <Comp />
              </PaneChrome>
            </div>
          );
        })()}
      </div>
    </div>
  );
}
```

```css
/* frontend/src/App.module.css */
.app { display: flex; flex-direction: column; height: 100vh; }
.grid { flex: 1; overflow-y: auto; padding: 4px; }
.gridInner { min-height: 100%; }
.overlay {
  position: fixed; inset: var(--topbar-height) 0 0 0;
  z-index: 50; background: var(--bg-deep); padding: 4px;
}
```

- [ ] **Step 3: Update PaneChrome header to include drag handle attribute**

In `PaneChrome.tsx`, add `data-drag-handle` to the header div:
```tsx
<div className={styles.header} data-drag-handle>
```

- [ ] **Step 4: Verify typecheck + dev server**

```bash
cd frontend && npx tsc --noEmit && npm run dev
```

Open browser, verify: TopBar renders, grid layout works, [+ ADD PANEL] dropdown shows categories.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/App.tsx frontend/src/App.module.css frontend/src/components/TopBar* frontend/src/components/PaneChrome*
git commit -m "feat(frontend): add TopBar + GridLayout app shell"
```

---

## Phase 3: SUI Integration Layer

### Task 7: Constants, Types, Formatters, Error Map

**Files:**
- Create: `frontend/src/lib/constants.ts`
- Create: `frontend/src/lib/types.ts`
- Create: `frontend/src/lib/format.ts`
- Create: `frontend/src/lib/errors.ts`
- Create: `frontend/tests/lib/format.test.ts`
- Create: `frontend/tests/lib/errors.test.ts`

**Context:**
- Types mirror Move structs. Constants from env vars.
- Format utils: address truncation, SUI amount (MIST → SUI), relative time.
- Error map: Move abort codes → human-readable messages.

- [ ] **Step 1: Write tests for format utils**

```typescript
// frontend/tests/lib/format.test.ts
import { describe, it, expect } from "vitest";
import { truncateAddress, formatSui, formatTimestamp, formatDuration } from "../../src/lib/format";

describe("format", () => {
  it("truncates address", () => {
    expect(truncateAddress("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"))
      .toBe("0x1234...cdef");
  });

  it("formats MIST to SUI", () => {
    expect(formatSui(1_000_000_000n)).toBe("1.000");
    expect(formatSui(500_000_000n)).toBe("0.500");
    expect(formatSui(1n)).toBe("0.000");
  });

  it("formats timestamp", () => {
    const ts = new Date("2026-03-21T12:00:00Z").getTime();
    const result = formatTimestamp(ts);
    expect(result).toContain("2026");
  });

  it("formats duration ms", () => {
    expect(formatDuration(3661000)).toBe("1h 1m");
    expect(formatDuration(120000)).toBe("2m 0s");
    expect(formatDuration(45000)).toBe("45s");
  });
});
```

- [ ] **Step 2: Write tests for error map**

```typescript
// frontend/tests/lib/errors.test.ts
import { describe, it, expect } from "vitest";
import { humanError } from "../../src/lib/errors";

describe("errors", () => {
  it("maps known Move error codes", () => {
    expect(humanError(0)).toBe("Not owner");
    expect(humanError(100)).toBe("Insufficient escrow");
    expect(humanError(204)).toBe("Listing inactive");
  });

  it("returns generic message for unknown codes", () => {
    expect(humanError(9999)).toContain("9999");
  });
});
```

- [ ] **Step 3: Run tests, verify fail**

```bash
cd frontend && npx vitest run tests/lib/
```

- [ ] **Step 4: Implement constants.ts**

```typescript
// frontend/src/lib/constants.ts
export const PACKAGE_IDS = {
  industrial_core: import.meta.env.VITE_PKG_INDUSTRIAL_CORE ?? "",
  work_order: import.meta.env.VITE_PKG_WORK_ORDER ?? "",
  marketplace: import.meta.env.VITE_PKG_MARKETPLACE ?? "",
} as const;

export const SHARED_OBJECTS = {
  work_order_board: import.meta.env.VITE_WORK_ORDER_BOARD ?? "",
  marketplace: import.meta.env.VITE_MARKETPLACE ?? "",
} as const;

export const WATCHER_URL = import.meta.env.VITE_WATCHER_URL ?? "http://localhost:3001";

export const CLOCK_ID = "0x6";

export const TYPE_STRINGS = {
  BlueprintOriginal: (pkg: string) => `${pkg}::blueprint::BlueprintOriginal`,
  BlueprintCopy: (pkg: string) => `${pkg}::blueprint::BlueprintCopy`,
  Recipe: (pkg: string) => `${pkg}::recipe::Recipe`,
  ProductionLine: (pkg: string) => `${pkg}::production_line::ProductionLine`,
  TriggerRule: (pkg: string) => `${pkg}::trigger_engine::TriggerRule`,
  WorkOrder: (pkg: string) => `${pkg}::work_order::WorkOrder`,
  BpoListing: (pkg: string) => `${pkg}::marketplace::BpoListing`,
  BpcListing: (pkg: string) => `${pkg}::marketplace::BpcListing`,
  LeaseAgreement: (pkg: string) => `${pkg}::lease::LeaseAgreement`,
} as const;
```

- [ ] **Step 5: Implement types.ts**

```typescript
// frontend/src/lib/types.ts
export interface Recipe {
  id: string;
  name: string;
  inputs: MaterialRequirement[];
  output: MaterialOutput;
  baseDurationMs: number;
  energyCost: number;
  creator: string;
}

export interface MaterialRequirement {
  itemTypeId: number;
  quantity: number;
}

export interface MaterialOutput {
  itemTypeId: number;
  quantity: number;
}

export interface BlueprintOriginal {
  id: string;
  recipeId: string;
  copiesMinted: number;
  maxCopies: number;
  materialEfficiency: number;
  timeEfficiency: number;
}

export interface BlueprintCopy {
  id: string;
  recipeId: string;
  sourceBpoId: string;
  usesRemaining: number;
  materialEfficiency: number;
  timeEfficiency: number;
}

export interface ProductionLine {
  id: string;
  owner: string;
  name: string;
  status: number; // 0=IDLE, 1=RUNNING
  recipeId: string;
  fuelReserve: number;
  jobsCompleted: number;
  currentJobEnd: number;
  operators: string[];
}

export interface WorkOrder {
  id: string;
  issuer: string;
  description: string;
  recipeId: string;
  quantityRequired: number;
  quantityDelivered: number;
  escrowValue: number;
  deadline: number;
  status: number;
  acceptor: string | null;
  priority: number;
  sourceEvent: string | null;
  deliveredAt: number | null;
}

export interface BpoListing {
  id: string;
  seller: string;
  price: number;
  active: boolean;
  bpoId: string;
}

export interface BpcListing {
  id: string;
  seller: string;
  price: number;
  active: boolean;
  bpcId: string;
}

export interface LeaseAgreement {
  id: string;
  lessor: string;
  lessee: string;
  expiry: number;
  dailyRate: number;
  depositValue: number;
  active: boolean;
}

export interface TriggerRule {
  id: string;
  productionLineId: string;
  conditionType: number;
  threshold: number;
  targetItemTypeId: number;
  enabled: boolean;
  lastTriggered: number;
  cooldownMs: number;
  autoRepeat: boolean;
}

// Status enums
export const PRODUCTION_STATUS = { IDLE: 0, RUNNING: 1 } as const;

export const ORDER_STATUS = {
  OPEN: 0, ACCEPTED: 1, DELIVERING: 2,
  DELIVERED: 3, COMPLETED: 4, CANCELLED: 5,
} as const;

export const ORDER_STATUS_LABEL: Record<number, string> = {
  0: "Open", 1: "Accepted", 2: "Delivering",
  3: "Delivered", 4: "Completed", 5: "Cancelled",
};

export const ORDER_PRIORITY_LABEL: Record<number, string> = {
  0: "Low", 1: "Normal", 2: "High", 3: "Critical",
};

export const TRIGGER_CONDITION = {
  OUTPUT_BUFFER_ABOVE: 0,
  INPUT_BUFFER_BELOW: 1,
  FUEL_BELOW: 2,
} as const;
```

- [ ] **Step 6: Implement format.ts**

```typescript
// frontend/src/lib/format.ts
const MIST_PER_SUI = 1_000_000_000n;

export function truncateAddress(addr: string, chars = 4): string {
  if (addr.length <= chars * 2 + 4) return addr;
  return `${addr.slice(0, chars + 2)}...${addr.slice(-chars)}`;
}

export function formatSui(mist: bigint | number): string {
  const val = typeof mist === "number" ? BigInt(mist) : mist;
  const whole = val / MIST_PER_SUI;
  const frac = val % MIST_PER_SUI;
  const fracStr = frac.toString().padStart(9, "0").slice(0, 3);
  return `${whole}.${fracStr}`;
}

export function formatTimestamp(ms: number): string {
  return new Date(ms).toLocaleString("en-US", {
    month: "short", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
    hour12: false,
  });
}

export function formatDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}
```

- [ ] **Step 7: Implement errors.ts**

```typescript
// frontend/src/lib/errors.ts
const ERROR_MAP: Record<number, string> = {
  // production_line
  0: "Not owner",
  1: "Not authorized operator",
  2: "Insufficient materials",
  3: "Production line busy",
  4: "Production not complete",
  11: "Recipe/blueprint mismatch",
  12: "Insufficient fuel",
  14: "Zero material after efficiency",
  17: "Max operators reached",
  18: "Invalid item type",
  20: "Insufficient output",
  // blueprint
  5: "No uses left on blueprint copy",
  6: "Max copies reached",
  13: "Efficiency out of range",
  // trigger_engine
  7: "Trigger disabled",
  8: "Trigger condition not met",
  9: "Trigger on cooldown",
  19: "Trigger/line mismatch",
  // work_order
  100: "Insufficient escrow",
  101: "Deadline too far",
  102: "Order already accepted",
  103: "Not issuer",
  104: "Not acceptor",
  105: "Wrong status for operation",
  106: "Delivery type mismatch",
  107: "Delivery quantity exceeds required",
  108: "Not expired",
  109: "Not delivered",
  110: "Auto-complete too early (72h not elapsed)",
  // marketplace
  200: "Listing price too low",
  201: "Not seller",
  202: "Insufficient payment",
  203: "Fee too high",
  204: "Listing inactive",
  // lease
  300: "Not lessee",
  301: "Not lessor",
  302: "Lease not expired",
  303: "Lease inactive",
};

export function humanError(code: number): string {
  return ERROR_MAP[code] ?? `Unknown error (code: ${code})`;
}
```

- [ ] **Step 8: Run tests, verify pass**

```bash
cd frontend && npx vitest run tests/lib/
```

- [ ] **Step 9: Typecheck**

```bash
cd frontend && npx tsc --noEmit
```

- [ ] **Step 10: Commit**

```bash
git add frontend/src/lib/ frontend/tests/lib/
git commit -m "feat(frontend): add constants, types, formatters, and error mapping"
```

---

### Task 8: PTB Builders

**Files:**
- Create: `frontend/src/lib/ptb/production.ts`
- Create: `frontend/src/lib/ptb/blueprint.ts`
- Create: `frontend/src/lib/ptb/workOrder.ts`
- Create: `frontend/src/lib/ptb/marketplace.ts`
- Create: `frontend/src/lib/ptb/lease.ts`
- Create: `frontend/src/lib/ptb/triggerEngine.ts`
- Create: `frontend/tests/lib/ptb/production.test.ts`
- Create: `frontend/tests/lib/ptb/blueprint.test.ts`
- Create: `frontend/tests/lib/ptb/workOrder.test.ts`
- Create: `frontend/tests/lib/ptb/marketplace.test.ts`
- Create: `frontend/tests/lib/ptb/lease.test.ts`
- Create: `frontend/tests/lib/ptb/triggerEngine.test.ts`

**Context:**
- Each PTB builder creates a `Transaction` object. Tests verify moveCall targets, argument count, and that returned objects are transferred.
- **CRITICAL**: `delist_bpo`/`delist_bpc` return objects that must be `transferObjects`'d back to sender.
- **CRITICAL**: `start_production` uses BPO (not BPC). BPC path is `public(package)`.
- `mint_bpc` returns `BlueprintCopy` — must transfer.
- Fleet integration: `create_order_from_damage_report` auto-sets CRITICAL priority.

- [ ] **Step 1: Write tests for production PTBs**

```typescript
// frontend/tests/lib/ptb/production.test.ts
import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";
import { buildStartProduction, buildCompleteProduction, buildDepositMaterials, buildDepositFuel, buildWithdrawOutput, buildAuthorizeOperator, buildRevokeOperator } from "../../../src/lib/ptb/production";

const PKG = "0xPKG";

describe("production PTBs", () => {
  it("buildStartProduction uses BPO (not BPC)", () => {
    const tx = buildStartProduction(PKG, "0xLINE", "0xRECIPE", "0xBPO");
    expect(tx).toBeInstanceOf(Transaction);
    // Verify the target includes start_production (not start_production_with_efficiency)
  });

  it("buildCompleteProduction builds valid tx", () => {
    const tx = buildCompleteProduction(PKG, "0xLINE");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildDepositMaterials builds valid tx", () => {
    const tx = buildDepositMaterials(PKG, "0xLINE", "0xRECIPE", 1, 100);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildDepositFuel builds valid tx", () => {
    const tx = buildDepositFuel(PKG, "0xLINE", 5000);
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildWithdrawOutput builds valid tx", () => {
    const tx = buildWithdrawOutput(PKG, "0xLINE", 2, 50);
    expect(tx).toBeInstanceOf(Transaction);
  });
});
```

- [ ] **Step 2: Write tests for marketplace PTBs (delist transfer critical)**

```typescript
// frontend/tests/lib/ptb/marketplace.test.ts
import { describe, it, expect } from "vitest";
import { Transaction } from "@mysten/sui/transactions";
import { buildListBpo, buildBuyBpo, buildDelistBpo, buildListBpc, buildBuyBpc, buildDelistBpc } from "../../../src/lib/ptb/marketplace";

const PKG = "0xPKG";

describe("marketplace PTBs", () => {
  it("buildDelistBpo transfers returned BPO to sender", () => {
    const tx = buildDelistBpo(PKG, "0xLISTING", "0xSENDER");
    expect(tx).toBeInstanceOf(Transaction);
    // The tx must contain both delist_bpo moveCall AND transferObjects
  });

  it("buildDelistBpc transfers returned BPC to sender", () => {
    const tx = buildDelistBpc(PKG, "0xLISTING", "0xSENDER");
    expect(tx).toBeInstanceOf(Transaction);
  });

  it("buildBuyBpo splits coin from gas", () => {
    const tx = buildBuyBpo(PKG, "0xMARKET", "0xLISTING", 1000000000n);
    expect(tx).toBeInstanceOf(Transaction);
  });
});
```

- [ ] **Step 3: Write tests for remaining PTBs (blueprint, workOrder, lease, triggerEngine)**

Similar pattern — verify `Transaction` instances are created, `mint_bpc` includes transferObjects for returned BPC.

- [ ] **Step 4: Run tests, verify fail**

```bash
cd frontend && npx vitest run tests/lib/ptb/
```

- [ ] **Step 5: Implement all PTB builders**

Create `frontend/src/lib/ptb/production.ts`:
```typescript
import { Transaction } from "@mysten/sui/transactions";
import { CLOCK_ID } from "../constants";

export function buildStartProduction(pkg: string, lineId: string, recipeId: string, bpoId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::start_production`,
    arguments: [tx.object(lineId), tx.object(recipeId), tx.object(bpoId), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildCompleteProduction(pkg: string, lineId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::complete_production`,
    arguments: [tx.object(lineId), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildDepositMaterials(pkg: string, lineId: string, recipeId: string, itemTypeId: number, quantity: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::deposit_materials`,
    arguments: [tx.object(lineId), tx.object(recipeId), tx.pure.u32(itemTypeId), tx.pure.u64(quantity)],
  });
  return tx;
}

export function buildDepositFuel(pkg: string, lineId: string, amount: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::deposit_fuel`,
    arguments: [tx.object(lineId), tx.pure.u64(amount)],
  });
  return tx;
}

export function buildWithdrawOutput(pkg: string, lineId: string, itemTypeId: number, quantity: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::withdraw_output`,
    arguments: [tx.object(lineId), tx.pure.u32(itemTypeId), tx.pure.u64(quantity)],
  });
  return tx;
}

export function buildAuthorizeOperator(pkg: string, lineId: string, operator: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::authorize_operator`,
    arguments: [tx.object(lineId), tx.pure.address(operator)],
  });
  return tx;
}

export function buildRevokeOperator(pkg: string, lineId: string, operator: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::revoke_operator`,
    arguments: [tx.object(lineId), tx.pure.address(operator)],
  });
  return tx;
}
```

Create `frontend/src/lib/ptb/blueprint.ts`:
```typescript
import { Transaction } from "@mysten/sui/transactions";

export function buildMintBpc(pkg: string, bpoId: string, uses: number, sender: string): Transaction {
  const tx = new Transaction();
  const bpc = tx.moveCall({
    target: `${pkg}::blueprint::mint_bpc`,
    arguments: [tx.object(bpoId), tx.pure.u64(uses)],
  });
  tx.transferObjects([bpc], sender);
  return tx;
}
```

Create `frontend/src/lib/ptb/workOrder.ts`:
```typescript
import { Transaction } from "@mysten/sui/transactions";
import { CLOCK_ID } from "../constants";

export function buildCreateWorkOrder(
  pkg: string, boardId: string, description: string, recipeId: string,
  quantity: number, escrowAmount: bigint, deadline: number, priority: number,
): Transaction {
  const tx = new Transaction();
  // Split exact escrow from gas coin (Coin<SUI> consumed by value)
  const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(escrowAmount)]);
  tx.moveCall({
    target: `${pkg}::work_order::create_work_order`,
    arguments: [
      tx.object(boardId), tx.pure.string(description), tx.pure.id(recipeId),
      tx.pure.u64(quantity), paymentCoin, tx.pure.u64(deadline),
      tx.pure.u8(priority), tx.object(CLOCK_ID),
    ],
  });
  return tx;
}

export function buildCreateOrderFromDamageReport(
  pkg: string, boardId: string, description: string, recipeId: string,
  quantity: number, escrowAmount: bigint, deadline: number, sourceEvent: string,
): Transaction {
  const tx = new Transaction();
  const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(escrowAmount)]);
  tx.moveCall({
    target: `${pkg}::fleet_integration::create_order_from_damage_report`,
    arguments: [
      tx.object(boardId), tx.pure.string(description), tx.pure.id(recipeId),
      tx.pure.u64(quantity), paymentCoin, tx.pure.u64(deadline),
      tx.pure.string(sourceEvent), tx.object(CLOCK_ID),
    ],
  });
  return tx;
}

export function buildAcceptWorkOrder(pkg: string, orderId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({ target: `${pkg}::work_order::accept_work_order`, arguments: [tx.object(orderId)] });
  return tx;
}

export function buildDeliverWorkOrder(pkg: string, orderId: string, itemTypeId: number, quantity: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::deliver_work_order`,
    arguments: [tx.object(orderId), tx.pure.u32(itemTypeId), tx.pure.u64(quantity), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildCompleteWorkOrder(pkg: string, orderId: string, boardId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::complete_work_order`,
    arguments: [tx.object(orderId), tx.object(boardId)],
  });
  return tx;
}

export function buildAutoCompleteWorkOrder(pkg: string, orderId: string, boardId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::auto_complete_work_order`,
    arguments: [tx.object(orderId), tx.object(boardId), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildCancelWorkOrder(pkg: string, orderId: string, boardId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::cancel_work_order`,
    arguments: [tx.object(orderId), tx.object(boardId)],
  });
  return tx;
}

export function buildCancelExpiredOrder(pkg: string, orderId: string, boardId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::cancel_expired_order`,
    arguments: [tx.object(orderId), tx.object(boardId), tx.object(CLOCK_ID)],
  });
  return tx;
}
```

Create `frontend/src/lib/ptb/marketplace.ts`:
```typescript
import { Transaction } from "@mysten/sui/transactions";

export function buildListBpo(pkg: string, marketId: string, bpoId: string, price: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::marketplace::list_bpo`,
    arguments: [tx.object(marketId), tx.object(bpoId), tx.pure.u64(price)],
  });
  return tx;
}

export function buildDelistBpo(pkg: string, listingId: string, sender: string): Transaction {
  const tx = new Transaction();
  const bpo = tx.moveCall({
    target: `${pkg}::marketplace::delist_bpo`,
    arguments: [tx.object(listingId)],
  });
  tx.transferObjects([bpo], sender);
  return tx;
}

export function buildBuyBpo(pkg: string, marketId: string, listingId: string, price: bigint): Transaction {
  const tx = new Transaction();
  // Split exact price from gas coin (&mut Coin<SUI>)
  const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(price)]);
  tx.moveCall({
    target: `${pkg}::marketplace::buy_bpo`,
    arguments: [tx.object(marketId), tx.object(listingId), paymentCoin],
  });
  return tx;
}

export function buildListBpc(pkg: string, marketId: string, bpcId: string, price: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::marketplace::list_bpc`,
    arguments: [tx.object(marketId), tx.object(bpcId), tx.pure.u64(price)],
  });
  return tx;
}

export function buildDelistBpc(pkg: string, listingId: string, sender: string): Transaction {
  const tx = new Transaction();
  const bpc = tx.moveCall({
    target: `${pkg}::marketplace::delist_bpc`,
    arguments: [tx.object(listingId)],
  });
  tx.transferObjects([bpc], sender);
  return tx;
}

export function buildBuyBpc(pkg: string, marketId: string, listingId: string, price: bigint): Transaction {
  const tx = new Transaction();
  const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(price)]);
  tx.moveCall({
    target: `${pkg}::marketplace::buy_bpc`,
    arguments: [tx.object(marketId), tx.object(listingId), paymentCoin],
  });
  return tx;
}
```

Create `frontend/src/lib/ptb/lease.ts`:
```typescript
import { Transaction } from "@mysten/sui/transactions";
import { CLOCK_ID } from "../constants";

export function buildCreateLease(
  pkg: string, bpoId: string, lessee: string,
  depositAmount: bigint, expiry: number, dailyRate: number,
): Transaction {
  const tx = new Transaction();
  // Split deposit from gas (Coin<SUI> consumed by value); BPO also consumed by value
  const [depositCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(depositAmount)]);
  tx.moveCall({
    target: `${pkg}::lease::create_lease`,
    arguments: [
      tx.object(bpoId), tx.pure.address(lessee), depositCoin,
      tx.pure.u64(expiry), tx.pure.u64(dailyRate),
    ],
  });
  return tx;
}

export function buildReturnLease(pkg: string, leaseId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::lease::return_lease`,
    arguments: [tx.object(leaseId)],
  });
  return tx;
}

export function buildForfeitLease(pkg: string, leaseId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::lease::forfeit_lease`,
    arguments: [tx.object(leaseId), tx.object(CLOCK_ID)],
  });
  return tx;
}
```

Create `frontend/src/lib/ptb/triggerEngine.ts`:
```typescript
import { Transaction } from "@mysten/sui/transactions";

export function buildCreateTriggerRule(
  pkg: string, lineId: string, conditionType: number, threshold: number,
  targetItemTypeId: number, autoRepeat: boolean, cooldownMs: number,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::trigger_engine::create_trigger_rule`,
    arguments: [
      tx.object(lineId), tx.pure.u8(conditionType), tx.pure.u64(threshold),
      tx.pure.u32(targetItemTypeId), tx.pure.bool(autoRepeat), tx.pure.u64(cooldownMs),
    ],
  });
  return tx;
}

export function buildToggleTrigger(pkg: string, ruleId: string, enabled: boolean): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::trigger_engine::toggle_trigger`,
    arguments: [tx.object(ruleId), tx.pure.bool(enabled)],
  });
  return tx;
}
```

- [ ] **Step 6: Run tests, verify pass**

```bash
cd frontend && npx vitest run tests/lib/ptb/
```

- [ ] **Step 7: Typecheck**

```bash
cd frontend && npx tsc --noEmit
```

- [ ] **Step 8: Commit**

```bash
git add frontend/src/lib/ptb/ frontend/tests/lib/ptb/
git commit -m "feat(frontend): add PTB builders for all contract functions"
```

---

### Task 9: React Query Hooks

**Files:**
- Create: `frontend/src/hooks/useProductionLines.ts`
- Create: `frontend/src/hooks/useRecipes.ts`
- Create: `frontend/src/hooks/useBlueprints.ts`
- Create: `frontend/src/hooks/useWorkOrders.ts`
- Create: `frontend/src/hooks/useMarketplace.ts`
- Create: `frontend/src/hooks/useLeases.ts`
- Create: `frontend/src/hooks/useTriggers.ts`
- Create: `frontend/src/hooks/useEvents.ts`
- Create: `frontend/src/hooks/useWatcher.ts`

**Context:**
- All hooks use `@tanstack/react-query` + `useSuiClient()` from dApp Kit.
- Owned objects: `getOwnedObjects` with StructType filter.
- Shared objects: `getObject` by ID.
- Marketplace listings: event query → fetch listing objects → filter active.
- Watcher: plain `fetch()` to REST API.
- Default refetch intervals from spec: 5s for most, 10s for overview, 3s for activity feed.

- [ ] **Step 1: Implement useProductionLines**

```typescript
// frontend/src/hooks/useProductionLines.ts
import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS, TYPE_STRINGS } from "../lib/constants";
import type { ProductionLine } from "../lib/types";

export function useProductionLines(lineIds: string[]) {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["production-lines", lineIds],
    queryFn: async (): Promise<ProductionLine[]> => {
      if (!lineIds.length) return [];
      const results = await client.multiGetObjects({
        ids: lineIds,
        options: { showContent: true },
      });
      return results
        .filter((r) => r.data?.content?.dataType === "moveObject")
        .map((r) => {
          const fields = (r.data!.content as any).fields;
          return {
            id: r.data!.objectId,
            owner: fields.owner,
            name: fields.name,
            status: Number(fields.status),
            recipeId: fields.recipe_id,
            fuelReserve: Number(fields.fuel_reserve),
            jobsCompleted: Number(fields.jobs_completed),
            currentJobEnd: Number(fields.current_job_end),
            operators: fields.operators ?? [],
          } satisfies ProductionLine;
        });
    },
    refetchInterval: 5000,
    enabled: lineIds.length > 0,
  });
}
```

- [ ] **Step 2: Implement useRecipes**

```typescript
// frontend/src/hooks/useRecipes.ts
// NOTE: Recipes are "global" (spec 4.4) — they may be owned by admin, not the current user.
// Use env-configured recipe IDs for discovery (hackathon approach).
// Alternative: event-based discovery via a "RecipeCreated" event (if contract emits one).
import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import type { Recipe } from "../lib/types";

// Comma-separated recipe object IDs from env
const RECIPE_IDS = (import.meta.env.VITE_RECIPE_IDS ?? "").split(",").filter(Boolean);

export function useRecipes() {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["recipes", RECIPE_IDS],
    queryFn: async (): Promise<Recipe[]> => {
      if (!RECIPE_IDS.length) return [];
      const results = await client.multiGetObjects({
        ids: RECIPE_IDS,
        options: { showContent: true },
      });
      return results
        .filter((r) => r.data?.content?.dataType === "moveObject")
        .map((r) => {
          const fields = (r.data!.content as any).fields;
          return {
            id: r.data!.objectId,
            name: fields.name,
            inputs: (fields.inputs ?? []).map((inp: any) => ({
              itemTypeId: Number(inp.fields.item_type_id),
              quantity: Number(inp.fields.quantity),
            })),
            output: {
              itemTypeId: Number(fields.output.fields.item_type_id),
              quantity: Number(fields.output.fields.quantity),
            },
            baseDurationMs: Number(fields.base_duration_ms),
            energyCost: Number(fields.energy_cost),
            creator: fields.creator,
          } satisfies Recipe;
        });
    },
    refetchInterval: 30000,
  });
}
```

- [ ] **Step 3: Implement useBlueprints**

```typescript
// frontend/src/hooks/useBlueprints.ts
import { useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS, TYPE_STRINGS } from "../lib/constants";
import type { BlueprintOriginal, BlueprintCopy } from "../lib/types";

export function useBlueprints() {
  const client = useSuiClient();
  const account = useCurrentAccount();

  const bpoQuery = useQuery({
    queryKey: ["bpos", account?.address],
    queryFn: async (): Promise<BlueprintOriginal[]> => {
      if (!account) return [];
      const { data } = await client.getOwnedObjects({
        owner: account.address,
        filter: { StructType: TYPE_STRINGS.BlueprintOriginal(PACKAGE_IDS.industrial_core) },
        options: { showContent: true },
      });
      return data.map((item) => {
        const f = (item.data!.content as any).fields;
        return {
          id: item.data!.objectId,
          recipeId: f.recipe_id,
          copiesMinted: Number(f.copies_minted),
          maxCopies: Number(f.max_copies),
          materialEfficiency: Number(f.material_efficiency),
          timeEfficiency: Number(f.time_efficiency),
        };
      });
    },
    refetchInterval: 10000,
  });

  const bpcQuery = useQuery({
    queryKey: ["bpcs", account?.address],
    queryFn: async (): Promise<BlueprintCopy[]> => {
      if (!account) return [];
      const { data } = await client.getOwnedObjects({
        owner: account.address,
        filter: { StructType: TYPE_STRINGS.BlueprintCopy(PACKAGE_IDS.industrial_core) },
        options: { showContent: true },
      });
      return data.map((item) => {
        const f = (item.data!.content as any).fields;
        return {
          id: item.data!.objectId,
          recipeId: f.recipe_id,
          sourceBpoId: f.source_bpo_id,
          usesRemaining: Number(f.uses_remaining),
          materialEfficiency: Number(f.material_efficiency),
          timeEfficiency: Number(f.time_efficiency),
        };
      });
    },
    refetchInterval: 10000,
  });

  return { bpos: bpoQuery, bpcs: bpcQuery };
}
```

- [ ] **Step 4: Implement useWorkOrders**

```typescript
// frontend/src/hooks/useWorkOrders.ts
import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { SHARED_OBJECTS } from "../lib/constants";
import type { WorkOrder } from "../lib/types";

export function useWorkOrders() {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["work-orders"],
    queryFn: async (): Promise<WorkOrder[]> => {
      // Get dynamic fields from WorkOrderBoard
      const { data: fields } = await client.getDynamicFields({
        parentId: SHARED_OBJECTS.work_order_board,
      });

      if (!fields.length) return [];

      const ids = fields.map((f) => f.objectId);
      const objects = await client.multiGetObjects({ ids, options: { showContent: true } });

      return objects
        .filter((o) => o.data?.content?.dataType === "moveObject")
        .map((o) => {
          const f = (o.data!.content as any).fields;
          return {
            id: o.data!.objectId,
            issuer: f.issuer,
            description: f.description,
            recipeId: f.recipe_id,
            quantityRequired: Number(f.quantity_required),
            quantityDelivered: Number(f.quantity_delivered),
            escrowValue: Number(f.escrow_value),
            deadline: Number(f.deadline),
            status: Number(f.status),
            acceptor: f.acceptor?.fields?.vec?.[0] ?? null,
            priority: Number(f.priority),
            sourceEvent: f.source_event?.fields?.vec?.[0] ?? null,
            deliveredAt: f.delivered_at?.fields?.vec?.[0] ? Number(f.delivered_at.fields.vec[0]) : null,
          } satisfies WorkOrder;
        });
    },
    refetchInterval: 5000,
  });
}
```

- [ ] **Step 5: Implement useMarketplace (event-based discovery)**

```typescript
// frontend/src/hooks/useMarketplace.ts
import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS, SHARED_OBJECTS } from "../lib/constants";
import type { BpoListing, BpcListing } from "../lib/types";

export function useMarketplace() {
  const client = useSuiClient();

  const bpoListings = useQuery({
    queryKey: ["market-bpo-listings"],
    queryFn: async (): Promise<BpoListing[]> => {
      // Discover listings via BpoListed events
      const { data: events } = await client.queryEvents({
        query: { MoveEventType: `${PACKAGE_IDS.marketplace}::marketplace::BpoListed` },
        order: "descending",
        limit: 50,
      });

      const listingIds = events.map((e) => (e.parsedJson as any).listing_id).filter(Boolean);
      if (!listingIds.length) return [];

      const objects = await client.multiGetObjects({
        ids: [...new Set(listingIds)],
        options: { showContent: true },
      });

      return objects
        .filter((o) => o.data?.content?.dataType === "moveObject")
        .map((o) => {
          const f = (o.data!.content as any).fields;
          return {
            id: o.data!.objectId,
            seller: f.seller,
            price: Number(f.price),
            active: f.active,
            bpoId: f.bpo_id ?? o.data!.objectId,
          };
        })
        .filter((l) => l.active);
    },
    refetchInterval: 10000,
  });

  const bpcListings = useQuery({
    queryKey: ["market-bpc-listings"],
    queryFn: async (): Promise<BpcListing[]> => {
      const { data: events } = await client.queryEvents({
        query: { MoveEventType: `${PACKAGE_IDS.marketplace}::marketplace::BpcListed` },
        order: "descending",
        limit: 50,
      });

      const listingIds = events.map((e) => (e.parsedJson as any).listing_id).filter(Boolean);
      if (!listingIds.length) return [];

      const objects = await client.multiGetObjects({
        ids: [...new Set(listingIds)],
        options: { showContent: true },
      });

      return objects
        .filter((o) => o.data?.content?.dataType === "moveObject")
        .map((o) => {
          const f = (o.data!.content as any).fields;
          return {
            id: o.data!.objectId,
            seller: f.seller,
            price: Number(f.price),
            active: f.active,
            bpcId: f.bpc_id ?? o.data!.objectId,
          };
        })
        .filter((l) => l.active);
    },
    refetchInterval: 10000,
  });

  return { bpoListings, bpcListings };
}
```

- [ ] **Step 6: Implement useLeases, useTriggers, useEvents, useWatcher**

Create `frontend/src/hooks/useLeases.ts`:
```typescript
import { useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS, TYPE_STRINGS } from "../lib/constants";
import type { LeaseAgreement } from "../lib/types";

export function useLeases() {
  const client = useSuiClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ["leases", account?.address],
    queryFn: async (): Promise<LeaseAgreement[]> => {
      if (!account) return [];
      // Query LeaseCreated events to discover lease IDs
      const { data: events } = await client.queryEvents({
        query: { MoveEventType: `${PACKAGE_IDS.marketplace}::lease::LeaseCreated` },
        order: "descending",
        limit: 50,
      });

      const leaseIds = events
        .map((e) => (e.parsedJson as any).lease_id)
        .filter(Boolean);
      if (!leaseIds.length) return [];

      const objects = await client.multiGetObjects({
        ids: [...new Set(leaseIds)],
        options: { showContent: true },
      });

      return objects
        .filter((o) => o.data?.content?.dataType === "moveObject")
        .map((o) => {
          const f = (o.data!.content as any).fields;
          return {
            id: o.data!.objectId,
            lessor: f.lessor,
            lessee: f.lessee,
            expiry: Number(f.expiry),
            dailyRate: Number(f.daily_rate),
            depositValue: Number(f.deposit_value),
            active: f.active,
          };
        })
        .filter((l) => l.lessor === account.address || l.lessee === account.address);
    },
    refetchInterval: 10000,
  });
}
```

Create `frontend/src/hooks/useTriggers.ts`:
```typescript
import { useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS, TYPE_STRINGS } from "../lib/constants";
import type { TriggerRule } from "../lib/types";

export function useTriggers() {
  const client = useSuiClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ["triggers", account?.address],
    queryFn: async (): Promise<TriggerRule[]> => {
      if (!account) return [];
      const { data } = await client.getOwnedObjects({
        owner: account.address,
        filter: { StructType: TYPE_STRINGS.TriggerRule(PACKAGE_IDS.industrial_core) },
        options: { showContent: true },
      });
      return data.map((item) => {
        const f = (item.data!.content as any).fields;
        return {
          id: item.data!.objectId,
          productionLineId: f.production_line_id,
          conditionType: Number(f.condition_type),
          threshold: Number(f.threshold),
          targetItemTypeId: Number(f.target_item_type_id),
          enabled: f.enabled,
          lastTriggered: Number(f.last_triggered),
          cooldownMs: Number(f.cooldown_ms),
          autoRepeat: f.auto_repeat,
        };
      });
    },
    refetchInterval: 5000,
  });
}
```

Create `frontend/src/hooks/useEvents.ts`:
```typescript
import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS } from "../lib/constants";

export interface ChainEvent {
  id: string;
  type: string;
  timestamp: number;
  parsedJson: Record<string, any>;
}

const EVENT_TYPES = [
  `${PACKAGE_IDS.industrial_core}::production_line::ProductionStartedEvent`,
  `${PACKAGE_IDS.industrial_core}::production_line::ProductionCompletedEvent`,
  `${PACKAGE_IDS.industrial_core}::trigger_engine::TriggerFiredEvent`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderCreated`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderAccepted`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderDelivered`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderCompleted`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderCancelled`,
  `${PACKAGE_IDS.marketplace}::marketplace::BpoListed`,
  `${PACKAGE_IDS.marketplace}::marketplace::BpoSold`,
  `${PACKAGE_IDS.marketplace}::marketplace::BpcListed`,
  `${PACKAGE_IDS.marketplace}::marketplace::BpcSold`,
  `${PACKAGE_IDS.marketplace}::lease::LeaseCreated`,
  `${PACKAGE_IDS.marketplace}::lease::LeaseReturned`,
  `${PACKAGE_IDS.marketplace}::lease::LeaseForfeited`,
];

export function useEvents(limit = 50) {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["events", limit],
    queryFn: async (): Promise<ChainEvent[]> => {
      // Query all event types in parallel for performance
      const results = await Promise.allSettled(
        EVENT_TYPES.map(async (eventType) => {
          const { data } = await client.queryEvents({
            query: { MoveEventType: eventType },
            order: "descending",
            limit: 10,
          });
          return data.map((e) => ({
            id: e.id.txDigest + "-" + e.id.eventSeq,
            type: eventType.split("::").pop() ?? "",
            timestamp: Number(e.timestampMs ?? 0),
            parsedJson: e.parsedJson as Record<string, any>,
          }));
        })
      );

      const allEvents: ChainEvent[] = results
        .filter((r): r is PromiseFulfilledResult<ChainEvent[]> => r.status === "fulfilled")
        .flatMap((r) => r.value);

      return allEvents
        .sort((a, b) => b.timestamp - a.timestamp)
        .slice(0, limit);
    },
    refetchInterval: 3000,
  });
}
```

Create `frontend/src/hooks/useWatcher.ts`:
```typescript
import { useQuery } from "@tanstack/react-query";
import { WATCHER_URL } from "../lib/constants";

export interface WatcherRule {
  name: string;
  description: string;
  enabled: boolean;
}

export interface WatcherTx {
  rule_name: string;
  tx_digest: string;
  status: string;
  error?: string;
  gas_used: number;
  created_at: number;
}

export function useWatcherStatus() {
  return useQuery({
    queryKey: ["watcher-status"],
    queryFn: async (): Promise<{ rules: WatcherRule[] }> => {
      const res = await fetch(`${WATCHER_URL}/status`);
      if (!res.ok) throw new Error(`Watcher API: ${res.status}`);
      return res.json();
    },
    refetchInterval: 5000,
  });
}

export function useWatcherHealth() {
  return useQuery({
    queryKey: ["watcher-health"],
    queryFn: async () => {
      const res = await fetch(`${WATCHER_URL}/health`);
      if (!res.ok) throw new Error(`Watcher API: ${res.status}`);
      return res.json();
    },
    refetchInterval: 10000,
  });
}

export function useWatcherTxLog(filters?: { status?: string; rule?: string; limit?: number }) {
  const params = new URLSearchParams();
  if (filters?.status) params.set("status", filters.status);
  if (filters?.rule) params.set("rule", filters.rule);
  if (filters?.limit) params.set("limit", String(filters.limit));

  return useQuery({
    queryKey: ["watcher-tx-log", filters],
    queryFn: async (): Promise<{ transactions: WatcherTx[] }> => {
      const res = await fetch(`${WATCHER_URL}/tx-log?${params}`);
      if (!res.ok) throw new Error(`Watcher API: ${res.status}`);
      return res.json();
    },
    refetchInterval: 5000,
  });
}
```

- [ ] **Step 7: Typecheck**

```bash
cd frontend && npx tsc --noEmit
```

- [ ] **Step 8: Commit**

```bash
git add frontend/src/hooks/
git commit -m "feat(frontend): add React Query hooks for all data sources"
```

---

## Phase 4: Pane Components — Dashboard

### Task 10: SystemOverview + ActivityFeed Panes

**Files:**
- Create: `frontend/src/panes/SystemOverview.tsx` + `.module.css`
- Create: `frontend/src/panes/ActivityFeed.tsx` + `.module.css`
- Modify: `frontend/src/config/paneRegistry.ts` (replace Placeholder imports)

**Context:**
- SystemOverview: stat cards showing counts and totals.
- ActivityFeed: scrollable event log with color-coded entries.

- [ ] **Step 1: Implement SystemOverview**

```tsx
// frontend/src/panes/SystemOverview.tsx
import { useProductionLines } from "../hooks/useProductionLines";
import { useWorkOrders } from "../hooks/useWorkOrders";
import { PRODUCTION_STATUS, ORDER_STATUS } from "../lib/types";
import styles from "./SystemOverview.module.css";

// Production line IDs from env (comma-separated)
const LINE_IDS = (import.meta.env.VITE_PRODUCTION_LINE_IDS ?? "").split(",").filter(Boolean);

export function SystemOverview() {
  const { data: lines } = useProductionLines(LINE_IDS);
  const { data: orders } = useWorkOrders();

  const stats = [
    { label: "Production Lines", value: lines?.length ?? 0 },
    { label: "Active Jobs", value: lines?.filter((l) => l.status === PRODUCTION_STATUS.RUNNING).length ?? 0 },
    { label: "Open Orders", value: orders?.filter((o) => o.status === ORDER_STATUS.OPEN).length ?? 0 },
    { label: "Completed Orders", value: orders?.filter((o) => o.status === ORDER_STATUS.COMPLETED).length ?? 0 },
    { label: "Total Jobs", value: lines?.reduce((sum, l) => sum + l.jobsCompleted, 0) ?? 0 },
    { label: "Fuel Reserve", value: lines?.reduce((sum, l) => sum + l.fuelReserve, 0) ?? 0 },
  ];

  return (
    <div className={styles.grid}>
      {stats.map((s) => (
        <div key={s.label} className={styles.card}>
          <div className={styles.value}>{s.value}</div>
          <div className={styles.label}>{s.label}</div>
        </div>
      ))}
    </div>
  );
}
```

```css
/* frontend/src/panes/SystemOverview.module.css */
.grid { display: flex; gap: 8px; flex-wrap: wrap; }
.card {
  flex: 1; min-width: 120px; padding: 12px;
  background: var(--bg-deep); border: 1px solid var(--border); border-radius: 2px;
  text-align: center;
}
.value { font-size: 24px; font-weight: 700; color: var(--accent); }
.label { font-size: 9px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-muted); margin-top: 4px; }
```

- [ ] **Step 2: Implement ActivityFeed**

```tsx
// frontend/src/panes/ActivityFeed.tsx
import { useEvents } from "../hooks/useEvents";
import { formatTimestamp } from "../lib/format";
import styles from "./ActivityFeed.module.css";

const EVENT_COLORS: Record<string, string> = {
  ProductionStartedEvent: "var(--status-info)",
  ProductionCompletedEvent: "var(--status-ok)",
  TriggerFiredEvent: "var(--status-warn)",
  WorkOrderCreated: "var(--status-info)",
  WorkOrderAccepted: "var(--accent)",
  WorkOrderDelivered: "var(--status-warn)",
  WorkOrderCompleted: "var(--status-ok)",
  WorkOrderCancelled: "var(--status-error)",
  BpoListed: "var(--status-info)",
  BpoSold: "var(--status-ok)",
  BpcListed: "var(--status-info)",
  BpcSold: "var(--status-ok)",
  LeaseCreated: "var(--status-info)",
  LeaseReturned: "var(--status-ok)",
  LeaseForfeited: "var(--status-error)",
};

export function ActivityFeed() {
  const { data: events, isLoading } = useEvents(50);

  if (isLoading) return <div className={styles.loading}>Loading events...</div>;

  return (
    <div className={styles.feed}>
      {events?.map((e) => (
        <div key={e.id} className={styles.entry}>
          <span className={styles.dot} style={{ background: EVENT_COLORS[e.type] ?? "var(--text-muted)" }} />
          <span className={styles.time}>{formatTimestamp(e.timestamp)}</span>
          <span className={styles.type}>{e.type.replace(/Event$/, "")}</span>
        </div>
      ))}
      {(!events || events.length === 0) && <div className={styles.empty}>No events yet</div>}
    </div>
  );
}
```

```css
/* frontend/src/panes/ActivityFeed.module.css */
.feed { display: flex; flex-direction: column; gap: 2px; }
.entry { display: flex; align-items: center; gap: 8px; padding: 3px 0; font-size: 11px; }
.dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
.time { color: var(--text-muted); font-size: 10px; white-space: nowrap; }
.type { color: var(--text-secondary); }
.loading, .empty { color: var(--text-muted); font-size: 11px; padding: 8px 0; }
```

- [ ] **Step 3: Update paneRegistry.ts with real component imports**

Replace the `Placeholder` for `system-overview` and `activity-feed` with:
```typescript
import { SystemOverview } from "../panes/SystemOverview";
import { ActivityFeed } from "../panes/ActivityFeed";
// ... update the PANE_DEFS array entries
```

- [ ] **Step 4: Typecheck**

```bash
cd frontend && npx tsc --noEmit
```

- [ ] **Step 5: Commit**

```bash
git add frontend/src/panes/SystemOverview* frontend/src/panes/ActivityFeed* frontend/src/config/paneRegistry.ts
git commit -m "feat(frontend): add SystemOverview and ActivityFeed panes"
```

---

## Phase 5: Pane Components — Production

### Task 11: ProductionMonitor + RecipeBrowser + MaterialInventory

**Files:**
- Create: `frontend/src/panes/ProductionMonitor.tsx` + `.module.css`
- Create: `frontend/src/panes/RecipeBrowser.tsx` + `.module.css`
- Create: `frontend/src/panes/MaterialInventory.tsx` + `.module.css`
- Modify: `frontend/src/config/paneRegistry.ts`

**Context:**
- ProductionMonitor: list of production lines with progress bars and action buttons.
  - Start production: select recipe + BPO (only BPO, not BPC).
  - Progress bar: `(now - start) / (end - start)` from `currentJobEnd`.
- RecipeBrowser: read-only table of all recipes.
- MaterialInventory: shows input/output buffer Bag contents for selected production line. Uses `getDynamicFields` on the Bag ID.
- All write actions use `useSignAndExecuteTransaction` from dApp Kit.

- [ ] **Step 1: Implement ProductionMonitor**

Full component with:
- Production line cards with status, recipe, fuel, jobs completed
- Progress bar for RUNNING lines (animated countdown)
- Action buttons: Start (BPO dropdown), Complete, Deposit Fuel
- Uses `useSignAndExecuteTransaction` for write actions
- Invalidates `production-lines` query on success

- [ ] **Step 2: Implement RecipeBrowser**

Simple read-only sortable table:
- Columns: Name, Inputs, Output, Duration, Energy
- Expandable row detail showing input/output breakdown

- [ ] **Step 3: Implement MaterialInventory**

Two-column layout:
- Input buffer quantities (from getDynamicFields on production line's input_buffer Bag)
- Output buffer quantities
- Deposit materials and withdraw output actions

- [ ] **Step 4: Update paneRegistry.ts**

- [ ] **Step 5: Typecheck**

```bash
cd frontend && npx tsc --noEmit
```

- [ ] **Step 6: Commit**

```bash
git add frontend/src/panes/ProductionMonitor* frontend/src/panes/RecipeBrowser* frontend/src/panes/MaterialInventory*
git commit -m "feat(frontend): add ProductionMonitor, RecipeBrowser, MaterialInventory panes"
```

---

## Phase 6: Pane Components — Blueprints

### Task 12: BlueprintInventory + BlueprintMint

**Files:**
- Create: `frontend/src/panes/BlueprintInventory.tsx` + `.module.css`
- Create: `frontend/src/panes/BlueprintMint.tsx` + `.module.css`
- Modify: `frontend/src/config/paneRegistry.ts`

**Context:**
- BlueprintInventory: table of owned BPOs/BPCs with ME/TE bars.
- BlueprintMint: form to mint BPC from selected BPO. `mint_bpc` returns `BlueprintCopy` — PTB must `transferObjects`.
- Validation: show `copies_minted` vs `max_copies`, disable if maxed.

- [ ] **Step 1: Implement BlueprintInventory**

Table columns: Type (BPO/BPC), Recipe ID, ME%, TE%, Copies/Uses
- ME/TE as 25-segment bar charts
- "Mint BPC" button on BPO rows (opens/focuses BlueprintMint pane)

- [ ] **Step 2: Implement BlueprintMint**

Form:
- BPO info display (recipe, ME, TE, copies minted/max)
- Uses input (number)
- Mint button → calls `buildMintBpc` → sign+execute → invalidate queries
- Disable if `copies_minted >= max_copies`

- [ ] **Step 3: Update paneRegistry.ts**

- [ ] **Step 4: Typecheck + commit**

```bash
cd frontend && npx tsc --noEmit
git add frontend/src/panes/BlueprintInventory* frontend/src/panes/BlueprintMint*
git commit -m "feat(frontend): add BlueprintInventory and BlueprintMint panes"
```

---

## Phase 7: Pane Components — Work Orders

### Task 13: WorkOrderBoard + WorkOrderDetail + WorkOrderCreate

**Files:**
- Create: `frontend/src/panes/WorkOrderBoard.tsx` + `.module.css`
- Create: `frontend/src/panes/WorkOrderDetail.tsx` + `.module.css`
- Create: `frontend/src/panes/WorkOrderCreate.tsx` + `.module.css`
- Modify: `frontend/src/config/paneRegistry.ts`

**Context:**
- WorkOrderBoard: filterable table with status tabs.
- WorkOrderDetail: full detail + action buttons based on status & role (issuer vs acceptor).
  - DELIVERED status: show refund split before cancel (OPEN → 100% issuer; ACCEPTED/DELIVERING → 90/10).
  - Auto-complete: 72h after delivery, acceptor can call `auto_complete_work_order`.
- WorkOrderCreate: form with recipe dropdown, quantity, escrow, deadline, priority.
  - If source_event is non-empty → use `fleet_integration::create_order_from_damage_report` instead.

- [ ] **Step 1: Implement WorkOrderBoard**

Status tab filter (All/Open/Accepted/Delivering/Delivered/Completed/Cancelled).
Columns: ID, Issuer, Recipe, Qty, Escrow, Deadline, Status, Priority.
Click row → opens WorkOrderDetail pane.

- [ ] **Step 2: Implement WorkOrderDetail**

Full detail view with conditional action buttons:
- OPEN: Accept (not issuer), Cancel (issuer)
- ACCEPTED: Mark delivering (acceptor)
- DELIVERING: Deliver items (acceptor) — item_type_id + quantity form
- DELIVERED: Complete (issuer), Auto-complete (acceptor, after 72h)
- Expired: Cancel expired (anyone) — show refund split preview

- [ ] **Step 3: Implement WorkOrderCreate**

Form with validation:
- Description (text), Recipe (dropdown from useRecipes), Quantity (number > 0)
- Escrow amount (SUI, min 1 MIST), Deadline (date picker, max 30 days)
- Priority (dropdown: Low/Normal/High/Critical)
- Source event (optional text) — auto-switches PTB target to fleet_integration
- Submit → buildCreateWorkOrder or buildCreateOrderFromDamageReport

- [ ] **Step 4: Update paneRegistry.ts**

- [ ] **Step 5: Typecheck + commit**

```bash
cd frontend && npx tsc --noEmit
git add frontend/src/panes/WorkOrder*
git commit -m "feat(frontend): add WorkOrder Board, Detail, and Create panes"
```

---

## Phase 8: Pane Components — Market

### Task 14: MarketListings + LeaseManager

**Files:**
- Create: `frontend/src/panes/MarketListings.tsx` + `.module.css`
- Create: `frontend/src/panes/LeaseManager.tsx` + `.module.css`
- Modify: `frontend/src/config/paneRegistry.ts`

**Context:**
- MarketListings: two tabs (BPO/BPC). Listings discovered via event query (no on-chain index).
  - Buy: `buy_bpo`/`buy_bpc` with payment coin.
  - List: `list_bpo`/`list_bpc` (select owned BPO/BPC + set price).
  - Delist: `delist_bpo`/`delist_bpc` — **MUST** `transferObjects` returned object back to sender.
  - Show fee_bps and calculated fee amount.
- LeaseManager: table of leases where user is lessor or lessee.
  - Create lease: select BPO, set lessee/expiry/rate/deposit.
  - Return lease (lessee, before expiry).
  - Forfeit lease (lessor, after expiry).

- [ ] **Step 1: Implement MarketListings**

Tabs: BPO Market / BPC Market.
Each listing card: Seller, Price, Blueprint details.
Actions: Buy, List, Delist (with transferObjects for returned object).

- [ ] **Step 2: Implement LeaseManager**

Table: Lease ID, Lessor, Lessee, Daily Rate, Expiry countdown, Deposit, Status.
Actions: Create (form), Return (lessee), Forfeit (lessor).

- [ ] **Step 3: Update paneRegistry.ts**

- [ ] **Step 4: Typecheck + commit**

```bash
cd frontend && npx tsc --noEmit
git add frontend/src/panes/MarketListings* frontend/src/panes/LeaseManager*
git commit -m "feat(frontend): add MarketListings and LeaseManager panes"
```

---

## Phase 9: Pane Components — Watcher + Trigger

### Task 15: WatcherStatus + TxLog + TriggerEngine

**Files:**
- Create: `frontend/src/panes/WatcherStatus.tsx` + `.module.css`
- Create: `frontend/src/panes/TxLog.tsx` + `.module.css`
- Create: `frontend/src/panes/TriggerEngine.tsx` + `.module.css`
- Modify: `frontend/src/config/paneRegistry.ts`

**Context:**
- WatcherStatus: reads from watcher REST API `/status`. Shows 11 rule handlers with enabled/disabled status.
- TxLog: reads from watcher REST API `/tx-log`. Filterable by status/rule.
- TriggerEngine: chain data (TriggerRule owned objects) + TriggerFiredEvent history.
  - Actions: create rule, toggle enable/disable, remove rule (currently no remove function — toggle disabled).

- [ ] **Step 1: Implement WatcherStatus**

List of 11 rules from `useWatcherStatus()`.
Each row: name, description, enabled badge (ok/muted).
Health indicator from `useWatcherHealth()`: uptime, last poll ago.
Graceful fallback if watcher is offline.

- [ ] **Step 2: Implement TxLog**

Scrollable table from `useWatcherTxLog()`.
Columns: Timestamp, TX Digest (truncated, link to explorer), Status (ok/error badge), Gas, Rule.
Filters: status dropdown, rule dropdown.
Graceful fallback if watcher offline.

- [ ] **Step 3: Implement TriggerEngine**

Split view:
- Top: active trigger rules from `useTriggers()`. Toggle enabled/disabled.
- Bottom: recent TriggerFiredEvent history from `useEvents`.
- Create rule form: production line (dropdown), condition type, threshold, target item type, cooldown.

- [ ] **Step 4: Update paneRegistry.ts with all remaining pane imports**

All 15 panes should now have real component imports (no more Placeholder).

- [ ] **Step 5: Typecheck + commit**

```bash
cd frontend && npx tsc --noEmit
git add frontend/src/panes/WatcherStatus* frontend/src/panes/TxLog* frontend/src/panes/TriggerEngine* frontend/src/config/paneRegistry.ts
git commit -m "feat(frontend): add WatcherStatus, TxLog, and TriggerEngine panes"
```

---

## Phase 10: Error Handling + Toast + Polish

### Task 16: Toast Notifications + Error Handling

**Files:**
- Create: `frontend/src/components/Toast.tsx` + `.module.css`
- Create: `frontend/src/hooks/useToast.ts`
- Modify: `frontend/src/App.tsx` (add Toast container)

**Context:**
- Simple toast system for TX success/failure notifications.
- Uses Move error code → human message mapping from `errors.ts`.
- Auto-dismiss after 5s, manual dismiss.

- [ ] **Step 1: Implement useToast hook (simple state-based)**

```typescript
// Context provider with addToast(message, variant) and auto-dismiss
```

- [ ] **Step 2: Implement Toast component**

Positioned fixed bottom-right. Styled with HUD theme. Variants: success (ok), error, info.

- [ ] **Step 3: Wire toast into PTB mutation callbacks**

In panes that use `useSignAndExecuteTransaction`, add `onSuccess`/`onError` callbacks that show toast.

- [ ] **Step 4: Add wallet-not-connected state to panes**

Panes with write actions: show disabled buttons + "Connect Wallet" when `useCurrentAccount()` is null.

- [ ] **Step 5: Typecheck + commit**

```bash
cd frontend && npx tsc --noEmit
git add frontend/src/components/Toast* frontend/src/hooks/useToast.ts frontend/src/App.tsx
git commit -m "feat(frontend): add toast notifications and error handling"
```

---

### Task 17: Final Integration + Typecheck + Build

**Files:**
- Modify: various — final wiring, import fixes
- Create: `frontend/.env` (from .env.example with testnet values)

**Context:**
- Final pass: ensure all 15 panes render, layout persistence works, wallet connects.
- Build must pass clean.

- [ ] **Step 1: Create .env with testnet package IDs**

Copy from `.env.example`, fill in deployed package IDs (or placeholders for now).

- [ ] **Step 2: Full typecheck**

```bash
cd frontend && npx tsc --noEmit
```

Fix any type errors.

- [ ] **Step 3: Build**

```bash
cd frontend && npm run build
```

Fix any build errors.

- [ ] **Step 4: Manual smoke test**

```bash
cd frontend && npm run dev
```

Verify:
- [ ] TopBar renders with logo, network badge, wallet connect
- [ ] Default panes load (SystemOverview, ProductionMonitor, WorkOrderBoard, ActivityFeed, TriggerEngine)
- [ ] [+ ADD PANEL] dropdown shows all 15 panes by category
- [ ] Panes can be dragged, resized, closed, minimized
- [ ] Layout persists across page reload
- [ ] Maximized pane fills viewport
- [ ] Wallet connection works (testnet)
- [ ] Panes show loading/empty states when no data

- [ ] **Step 5: Commit**

```bash
git add frontend/
git commit -m "feat(frontend): final integration and build verification"
```

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 0 | 1 | Watcher REST API |
| 1 | 2-3 | Project scaffold + HUD theme |
| 2 | 4-6 | Core shell (PaneChrome, layout, TopBar, GridLayout) |
| 3 | 7-9 | SUI integration (constants, types, PTB builders, hooks) |
| 4 | 10 | Dashboard panes (SystemOverview, ActivityFeed) |
| 5 | 11 | Production panes (Monitor, Recipes, Materials) |
| 6 | 12 | Blueprint panes (Inventory, Mint) |
| 7 | 13 | Work order panes (Board, Detail, Create) |
| 8 | 14 | Market panes (Listings, Lease) |
| 9 | 15 | Watcher + Trigger panes |
| 10 | 16-17 | Error handling, toast, polish, final build |

**Total: 17 tasks, ~17 commits**

**Dependencies:** Tasks are sequential within phases. Phase 0 (watcher API) is independent and can run in parallel with Phase 1-2. Phase 3 (SUI integration) must complete before Phase 4-9 (panes). Phase 10 requires all panes.

**Parallel opportunities for subagent execution:**
- Level A: Task 1 (watcher API) ∥ Task 2 (scaffold) ∥ Task 3 (theme)
- Level B: Task 4 (PaneChrome) ∥ Task 7 (constants/types/format)
- Level C: Task 5 (registry/layout) + Task 8 (PTB builders) — after Level B
- Level D: Task 6 (App shell) + Task 9 (hooks) — after Level C
- Level E: Tasks 10-15 (panes) — sequential but each is independent once hooks exist
- Level F: Tasks 16-17 (polish) — after all panes

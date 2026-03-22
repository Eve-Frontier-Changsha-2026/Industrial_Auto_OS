# Industrial Auto OS — Frontend Design Spec

> EVE Frontier HUD-style industrial management dashboard
> Date: 2026-03-21
> Status: Reviewed (12 issues fixed from spec review)
> Scope: Task 14-18 (React Frontend)

---

## 1. Overview

Full EVE Online-style HUD interface for Industrial Auto OS. All functionality is presented as freely draggable, resizable window panes — no fixed page routing. Users arrange their workspace like a capsuleer cockpit.

### Design Principles

- **Information density** — show maximum data per pixel, monospace fonts, compact spacing
- **Zero chrome waste** — every pixel serves a purpose; no decorative whitespace
- **Amber Industrial palette** — near-black background + amber/gold borders + warm gold text
- **Persistent layout** — user's pane arrangement saved to localStorage, restored on reload
- **Real-time feel** — polling-based data refresh, animated progress bars, live activity feed

---

## 2. Visual Design

### Color Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `--bg-deep` | `#0c0a04` | Page background |
| `--bg-panel` | `#110e04` | Panel body |
| `--bg-header` | `#1a1408` | Panel title bar |
| `--border` | `#3a2d0a` | Panel borders, dividers |
| `--text-primary` | `#e8d088` | Primary text |
| `--text-secondary` | `#b89a40` | Secondary text |
| `--text-muted` | `#8a7530` | Labels, hints |
| `--accent` | `#c9a84c` | Headings, active elements |
| `--status-ok` | `#4caf50` | Running, completed, healthy |
| `--status-warn` | `#e8a82d` | Delivering, cooldown, low |
| `--status-error` | `#c94040` | Error, expired, critical |
| `--status-info` | `#5b8fb9` | Open, idle, informational |
| `--progress-fill` | linear-gradient(90deg, #8a6b10, #c9a84c) | Progress bars |

### Typography

- **Font**: `'JetBrains Mono', 'Fira Code', monospace` — all text is monospace
- **Panel title**: 9-11px, bold, uppercase, letter-spacing: 2px
- **Body text**: 12-13px
- **Data values**: 13px, `--text-primary`
- **Labels**: 11px, `--text-muted`, uppercase

### Panel Chrome

Every pane shares the same chrome structure:

```
┌─ [amber header bar] ──────────── [_] [□] [×] ─┐
│  PANEL TITLE                    minimize/max/close │
├────────────────────────────────────────────────────┤
│                                                    │
│  Panel content                                     │
│                                                    │
└────────────────────────────────────────────────────┘
```

- Header: `--bg-header` background, 1px `--border` bottom
- Body: `--bg-panel` background
- Border: 1px solid `--border`, border-radius: 2px
- Resize handle: bottom-right corner, subtle amber grip dots
- Drag: entire header bar is drag handle

---

## 3. Architecture

### Tech Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Framework | React 18 + Vite | Fast HMR, SUI dApp Kit native support |
| Pane system | react-grid-layout | Proven draggable/resizable grid, localStorage persistence |
| State / data | @tanstack/react-query v5 | Polling-based chain data fits query paradigm |
| SUI wallet | @mysten/dapp-kit | Wallet connection, PTB signing |
| SUI SDK | @mysten/sui | Object queries, PTB construction |
| Charts | recharts | Production efficiency, gas usage graphs |
| Styling | CSS Modules | Scoped styles, no runtime overhead, full control for HUD theme |

### Directory Structure

```
frontend/
├── index.html
├── vite.config.ts
├── tsconfig.json
├── package.json
├── public/
│   └── fonts/                    # JetBrains Mono
├── src/
│   ├── main.tsx                  # App entry, providers
│   ├── App.tsx                   # Top bar + GridLayout + PaneManager
│   ├── theme/
│   │   ├── variables.css         # CSS custom properties (color palette)
│   │   ├── global.css            # Reset, base styles, scrollbar
│   │   └── panel.module.css      # Shared panel chrome styles
│   ├── components/
│   │   ├── TopBar.tsx            # Logo, wallet connect, network indicator
│   │   ├── PaneChrome.tsx        # Reusable pane wrapper (title bar, min/max/close)
│   │   ├── PaneMenu.tsx          # [+ Add Panel] dropdown
│   │   └── StatusBadge.tsx       # Colored status indicator
│   ├── panes/
│   │   ├── SystemOverview.tsx    # Summary stats
│   │   ├── ActivityFeed.tsx      # Real-time event stream
│   │   ├── ProductionMonitor.tsx # Production line status + progress
│   │   ├── RecipeBrowser.tsx     # Recipe list + details
│   │   ├── MaterialInventory.tsx # Input/output buffer quantities
│   │   ├── BlueprintInventory.tsx# BPO/BPC list with ME/TE
│   │   ├── BlueprintMint.tsx     # Mint BPC form
│   │   ├── WorkOrderBoard.tsx    # Order list + status filter
│   │   ├── WorkOrderDetail.tsx   # Single order + action buttons
│   │   ├── WorkOrderCreate.tsx   # Create order form
│   │   ├── MarketListings.tsx    # BPO/BPC listings + buy
│   │   ├── LeaseManager.tsx      # Lease contracts
│   │   ├── WatcherStatus.tsx     # 11 rule handlers status
│   │   ├── TxLog.tsx             # Transaction history
│   │   └── TriggerEngine.tsx     # Trigger rules + cooldowns
│   ├── hooks/
│   │   ├── useProductionLines.ts # Query production line objects
│   │   ├── useRecipes.ts         # Query recipe objects
│   │   ├── useBlueprints.ts      # Query BPO/BPC owned by user
│   │   ├── useWorkOrders.ts      # Query work order board
│   │   ├── useMarketplace.ts     # Query marketplace listings
│   │   ├── useLeases.ts          # Query lease agreements
│   │   ├── useTriggers.ts        # Query trigger rules
│   │   ├── useEvents.ts          # Subscribe to SUI events
│   │   └── useLayout.ts          # Grid layout persistence
│   ├── lib/
│   │   ├── ptb/                  # PTB builders per contract function
│   │   │   ├── production.ts     # start/complete production, deposit materials, deposit fuel
│   │   │   ├── blueprint.ts      # mint BPO/BPC (handle returned objects)
│   │   │   ├── workOrder.ts      # create/accept/deliver/complete/auto-complete/cancel-expired
│   │   │   ├── fleetIntegration.ts # create_order_from_damage_report (auto CRITICAL priority)
│   │   │   ├── marketplace.ts    # list/buy/delist BPO/BPC (delist must transfer returned object)
│   │   │   ├── lease.ts          # create/return/forfeit lease
│   │   │   └── triggerEngine.ts  # create/remove/toggle trigger rules
│   │   ├── constants.ts          # Package IDs, object IDs, type strings
│   │   ├── types.ts              # TypeScript types mirroring Move structs
│   │   └── format.ts             # Format addresses, amounts, timestamps
│   └── config/
│       └── defaultLayout.ts      # Default pane positions for first-time users
```

### Data Flow

```
SUI RPC ──polling──→ @tanstack/react-query cache ──→ React hooks ──→ Pane components
                                                                         │
User action ──→ PTB builder (lib/ptb/*) ──→ dApp Kit sign+execute ──→ invalidate queries
```

- **Read path**: `useQuery` with `refetchInterval` (5s default, configurable per pane)
- **Write path**: `useMutation` → PTB build → `useSignAndExecuteTransaction` → `queryClient.invalidateQueries`
- **Events**: `suiClient.subscribeEvent` for real-time Activity Feed (fallback to polling)

---

## 4. Pane Specifications

### 4.1 System Overview

- **Data**: Count of production lines, active jobs, open work orders, gas pool balance, total jobs completed
- **Layout**: 4-6 stat cards in a row, each with icon + value + label
- **Refresh**: 10s

### 4.2 Activity Feed

- **Data**: SUI events from all 3 packages (ProductionStarted/Completed, WorkOrderCreated/Accepted/Delivered/Completed, BpoListed/Sold, LeaseCreated/Returned/Forfeited, TriggerFired)
- **Layout**: Scrollable log, newest on top, timestamp + event type + details
- **Color coding**: Each event type has a distinct icon/color
- **Refresh**: WebSocket subscription (fallback: 3s polling)

### 4.3 Production Monitor

- **Data**: All production lines owned by or operated by current wallet
- **Layout**: List of production lines, each showing:
  - Name, status (IDLE/RUNNING), recipe name
  - Progress bar with ETA countdown (if running)
  - Jobs completed count
  - Fuel reserve level
  - Operators list
- **Actions**: Start production (select recipe + BPO), complete production, deposit materials, withdraw output, deposit fuel, add/remove operator
- **Note**: `start_production` only accepts `&BlueprintOriginal`. BPC-based production (`start_production_with_efficiency`) is `public(package)` and cannot be called from external PTB. Frontend only supports BPO-based starts; BPC-based starts are watcher-only (via trigger_engine same-package call).
- **Refresh**: 5s

### 4.4 Recipe Browser

- **Data**: All Recipe objects (global, not user-specific)
- **Layout**: Sortable table — Name, Inputs (item_type_ids + quantities), Output, Duration, Energy Cost
- **Detail view**: Click row to expand input/output breakdown
- **Read-only**: No write actions (recipes are created via CLI/PTB)

### 4.5 Material Inventory

- **Data**: `input_buffer` and `output_buffer` Bags from production lines
- **Layout**: Two columns — Input Buffer (raw materials) / Output Buffer (products)
- **Each row**: item_type_id, quantity, bar chart relative to recipe requirement
- **Actions**: Deposit materials (coin/object transfer), withdraw output
- **Refresh**: 5s

### 4.6 Blueprint Inventory

- **Data**: BPO and BPC objects owned by current wallet
- **Layout**: Table — Type (BPO/BPC), Recipe, ME%, TE%, Copies minted/max (BPO) or Uses remaining (BPC)
- **Visual**: ME/TE as small bar charts (0-25 range)
- **Actions**: Select BPO to mint BPC (opens BlueprintMint pane)

### 4.7 Blueprint Mint

- **Data**: Selected BPO details
- **Layout**: Form — BPO info display, uses input, mint button
- **Actions**: `mint_bpc(bpo, uses, ctx)` — validates max_copies not reached
- **Validation**: Show copies_minted vs max_copies, disable if maxed

### 4.8 Work Order Board

- **Data**: All work orders from WorkOrderBoard (Table<ID, bool>)
- **Layout**: Filterable table — ID, Issuer, Recipe, Qty required/delivered, Escrow, Deadline, Status, Priority
- **Filters**: Status tabs (All / Open / Accepted / Delivering / Completed / Cancelled)
- **Click**: Opens WorkOrderDetail for selected order
- **Refresh**: 5s

### 4.9 Work Order Detail

- **Data**: Single WorkOrder object
- **Layout**: Full detail view — all fields + action buttons based on status & role
- **Actions by status**:
  - OPEN: Accept (if not issuer), Cancel (if issuer)
  - ACCEPTED: Mark delivering (if acceptor)
  - DELIVERING: Deliver items (if acceptor)
  - DELIVERED: Complete + release escrow (if issuer), Auto-complete after 72h (if acceptor, calls `auto_complete_work_order`)
  - Any: Cancel expired (if past deadline, anyone) — show refund split before confirm: OPEN → 100% issuer; ACCEPTED/DELIVERING → 90% issuer / 10% acceptor

### 4.10 Work Order Create

- **Data**: Form inputs
- **Layout**: Form — Description, Recipe ID (dropdown from recipes), Quantity, Escrow amount (SUI), Deadline, Priority, Source event
- **Validation**: Min escrow (1 MIST), max deadline (30 days), quantity > 0
- **Actions**: `create_work_order` → signs and submits

### 4.11 Market Listings

- **Data**: Active BpoListing and BpcListing objects from Marketplace
- **Layout**: Two tabs — BPO Market / BPC Market
- **Each listing**: Seller, Price (SUI), Blueprint details (recipe, ME/TE)
- **Actions**:
  - Buy: `buy_bpo` / `buy_bpc` — pay price + fee
  - List own: `list_bpo` / `list_bpc` — set price
  - Delist: `delist_bpo` / `delist_bpc` (if seller)
- **Fee display**: Show fee_bps and calculated fee amount

### 4.12 Lease Manager

- **Data**: LeaseAgreement objects where user is lessor or lessee
- **Layout**: Table — Lease ID, Lessor, Lessee, BPO details, Daily rate, Expiry, Deposit, Status
- **Actions**:
  - Create lease (if BPO owner): select BPO, set lessee/expiry/rate/deposit
  - Return lease (if lessee, before expiry)
  - Forfeit lease (if lessor, after expiry)
- **Visual**: Expiry countdown, deposit amount in SUI

### 4.13 Watcher Status

- **Data**: Watcher REST API or local SQLite read
- **Layout**: List of 11 rule handlers, each showing:
  - Name, enabled/disabled toggle (read-only, config-driven)
  - Last execution timestamp
  - Success/fail count
  - Current state (e.g., cooldown remaining)
- **Note**: This pane reads from the watcher's own data source, not directly from chain

### 4.14 TX Log

- **Data**: Watcher's `tx_log` SQLite table or chain events
- **Layout**: Scrollable table — Timestamp, TX digest (linkable to explorer), Status (success/fail), Gas cost, Rule handler that triggered it
- **Filters**: By status, by rule handler
- **Refresh**: 5s

### 4.15 Trigger Engine

- **Data**: TriggerRule objects from chain + TriggerFiredEvent history
- **Layout**:
  - Active rules list: rule ID, condition type, threshold, cooldown, last fired
  - History: recent trigger fires with timestamps and actions taken
- **Actions**: Create trigger rule, remove trigger rule (owner only), toggle trigger enabled/disabled (owner only, calls `toggle_trigger`)
- **Refresh**: 5s

---

## 5. Pane Management System

### Grid Layout

- **Library**: `react-grid-layout` with `WidthProvider` + `Responsive`
- **Breakpoints**: xl (1600+), lg (1200+), md (996+) — no mobile (this is a desktop HUD)
- **Grid**: 24 columns, row height 30px
- **Margins**: 4px gap between panes

### Pane Lifecycle

1. **Default layout**: First visit loads `defaultLayout.ts` — SystemOverview, ProductionMonitor, WorkOrderBoard, ActivityFeed, TriggerEngine
2. **Add pane**: `[+ Add Panel]` button in top bar → dropdown of available panes → click to add at next open position
3. **Remove pane**: Close button (×) on pane chrome → removes from layout
4. **Minimize**: Collapse to title bar only (height: 1 row)
5. **Maximize**: Expand to fill viewport (overlay mode)
6. **Persistence**: Layout JSON saved to `localStorage` key `industrial-auto-os-layout`, restored on load

### Pane Registry

```typescript
interface PaneDefinition {
  id: string;            // unique key
  title: string;         // display name for header
  component: React.FC;   // pane content component
  defaultSize: { w: number; h: number }; // grid units
  minSize: { w: number; h: number };
  category: 'dashboard' | 'production' | 'blueprint' | 'orders' | 'market' | 'watcher' | 'trigger';
}
```

---

## 6. Top Bar

Fixed at top, not part of grid layout.

```
┌─────────────────────────────────────────────────────────────────┐
│ ⬡ INDUSTRIAL AUTO OS    │ [+ Add Panel] │ testnet │ 🔗 0x7f..e9 │
└─────────────────────────────────────────────────────────────────┘
```

- **Left**: Logo + app name (amber, uppercase, monospace)
- **Center**: `[+ Add Panel]` button
- **Right**: Network indicator (testnet/mainnet), Wallet connect button (dApp Kit `ConnectButton` restyled)
- **Height**: 36px, `--bg-header` background, bottom border `--border`

---

## 7. SUI Integration Details

### Package IDs & Object IDs

Stored in `lib/constants.ts`, loaded from environment variables:

```typescript
export const PACKAGE_IDS = {
  industrial_core: import.meta.env.VITE_PKG_INDUSTRIAL_CORE,
  work_order: import.meta.env.VITE_PKG_WORK_ORDER,
  marketplace: import.meta.env.VITE_PKG_MARKETPLACE,
};

export const SHARED_OBJECTS = {
  work_order_board: import.meta.env.VITE_WORK_ORDER_BOARD,
  marketplace: import.meta.env.VITE_MARKETPLACE,
};
```

### Query Patterns

- **Owned objects** (blueprints, recipes, trigger rules): `suiClient.getOwnedObjects({ owner, filter: { StructType } })`
  - `BlueprintOriginal`: `${PKG}::blueprint::BlueprintOriginal`
  - `BlueprintCopy`: `${PKG}::blueprint::BlueprintCopy`
  - `Recipe`: `${PKG}::recipe::Recipe`
  - `TriggerRule`: `${PKG}::trigger_engine::TriggerRule` (owned, not shared)
- **Shared objects** (production lines, work order board, marketplace): `suiClient.getObject({ id, options: { showContent: true } })`
- **Dynamic fields** (Bag items, DOF listings): `suiClient.getDynamicFields({ parentId })` + `getDynamicFieldObject`
  - Production line `input_buffer`/`output_buffer`: Bag entries keyed by `u32` item_type_id
  - Marketplace BPO/BPC in listings: DOF keyed by `ListedBpo{}`/`ListedBpc{}`
- **Marketplace listing discovery**: No on-chain index exists. Discover listings by querying `BpoListed`/`BpcListed` events with cursor pagination (`suiClient.queryEvents`). For each listing event, fetch the listing object and check `active == true`. Cache listing IDs client-side.
- **Events**: `suiClient.queryEvents({ query: { MoveEventType } })` with cursor pagination

### PTB Patterns

All write operations build a `Transaction` (PTB) and use dApp Kit to sign:

```typescript
// Example: start production (BPO-based, the only PTB-callable path)
const tx = new Transaction();
tx.moveCall({
  target: `${PKG}::production_line::start_production`,
  arguments: [
    tx.object(productionLineId),  // &mut ProductionLine (shared)
    tx.object(recipeId),          // &Recipe
    tx.object(bpoId),             // &BlueprintOriginal (NOT BPC — BPC path is public(package) only)
    tx.object(clockId),           // &Clock
  ],
});
```

### PTB Return Value Handling

Some contract functions return Move objects that must be consumed in the PTB:

- `delist_bpo` returns `BlueprintOriginal` → must `tx.transferObjects([result], senderAddress)`
- `delist_bpc` returns `BlueprintCopy` → must `tx.transferObjects([result], senderAddress)`
- `mint_bpc` returns `BlueprintCopy` → must `tx.transferObjects([result], senderAddress)`
- `mint_bpo` returns `BlueprintOriginal` → must `tx.transferObjects([result], senderAddress)`

Failure to consume returned objects will abort the transaction.

### Fleet Integration PTB

When creating a work order with a source event (fleet damage), use `fleet_integration::create_order_from_damage_report` instead of `work_order::create_work_order_with_source`. This auto-sets priority to CRITICAL and cannot be overridden. The Work Order Create form should detect non-empty source_event and switch PTB target accordingly.

---

## 8. Watcher Integration

The Watcher (Task 11-13) runs as a separate Node.js process with SQLite persistence.

### Option A: REST API wrapper (recommended for hackathon)

Add a minimal Express endpoint to watcher that exposes:
- `GET /status` — rule handler states
- `GET /tx-log` — recent transactions
- `GET /health` — uptime, last poll timestamp

Frontend polls these endpoints for WatcherStatus and TxLog panes.

### Option B: Direct chain events only

WatcherStatus pane shows only on-chain data (trigger events, production events). Less detailed but zero extra infra.

**Decision**: Option A for hackathon — minimal effort, maximum visibility.

---

## 9. Error Handling

- **Wallet not connected**: Panes show data (read-only) but disable action buttons with "Connect Wallet" prompt
- **Transaction failure**: Toast notification with error code mapping to human-readable message (e.g., `E_NOT_OWNER` → "You are not the owner of this production line")
- **RPC failure**: Pane shows "Connection lost" overlay with retry button, auto-retry after 10s
- **Stale data**: Show "last updated X seconds ago" in pane footer when refresh fails

---

## 10. Scope Boundaries

### In Scope
- All 15 panes listed above
- Full read/write for all 3 Move packages
- Wallet connection + transaction signing
- Layout persistence
- Watcher REST API integration

### Out of Scope
- Mobile responsive (desktop HUD only)
- Multi-language / i18n
- User authentication beyond wallet
- Pane theming / custom colors
- Sound effects / notifications
- Keyboard shortcuts for pane management
- `create_production_line` — admin/CLI only, not exposed in UI
- `mint_bpo` — admin/CLI only (BPO creation is a privileged operation)
- `destroy_empty_bpc` — CLI only (burn 0-use BPC)
- BPC-based production start — `start_production_with_efficiency` is `public(package)`, watcher-only path

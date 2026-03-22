# Task 20: Demo + Docs — Design Spec

> Date: 2026-03-23
> Status: Approved (post review, 8 fixes applied)
> Scope: Hackathon submission README + frontend demo guide

---

## 1. Deliverables

| File | Purpose |
|------|---------|
| `README_zh.md` | Current Chinese README content preserved as-is |
| `README.md` | New British English README for hackathon submission |
| `docs/demo-guide.md` | Frontend-focused demo walkthrough (EN + zh-TW) |
| `docs/images/.gitkeep` | Placeholder directory for screenshot assets |

## 2. README.md Structure

1. **Header**: Project name + one-line tagline
2. **TL;DR**: 3 sentences — what, why, impact
3. **Architecture**: Mermaid diagram — Core + Satellite pattern (on-chain, off-chain watcher, frontend)
4. **Key Features**: ~8 bullet points
5. **Tech Stack**: Table (Contracts / Watcher / Frontend)
6. **Testnet Deployment**: All 3 packages + 3 shared objects explicitly:
   - Packages: `industrial_core`, `work_order`, `marketplace`
   - Shared objects: `WorkOrderBoard`, `Marketplace`, `MarketplaceAdminCap`
   - Source: `tasks/deployment-testnet.md` (Package IDs + Shared Object IDs only; tx digests omitted — some are incomplete)
7. **Quick Start**: Prerequisites (incl. testnet SUI via faucet) → clone → build → watcher → frontend
8. **Demo**: Link to `docs/demo-guide.md`
9. **Project Structure**: Compact tree
10. **Test Results**: 165 Move + 73 Watcher + 36 Frontend + 5 E2E = 279
11. **Team / Credits**
12. **Licence**: MIT (confirm with team; mark TBD if unconfirmed)
13. **Chinese Version**: Link to `README_zh.md`

Language: British English throughout. No Chinese content in README.md.

## 3. docs/demo-guide.md Structure

### Prerequisites

- Sui wallet (Slush / Sui Wallet) on testnet
- Testnet SUI from faucet (https://faucet.sui.io)
- Node.js 18+

### Setup (not counted as a demo step)

- `npm install` → `npm run dev` → open localhost:5173

### 10 Demo Steps

1. Connect Wallet — TopBar shows address
2. Browse Recipes — RecipeBrowser pane, see Tritanium Refining
3. View Production Line — ProductionMonitor pane, see Assembly Line Alpha
4. Start Production — sign tx → toast success → status: Producing
5. Complete Production — sign tx → outputs credited
6. Browse Blueprints — BlueprintInventory pane, see BPO
7. List BPO on Marketplace — MarketListings pane, set price, sign tx
8. Create Work Order — WorkOrderCreate pane, fill form, set reward, sign tx
9. View Work Order Board — WorkOrderBoard pane, see created order + WorkOrderDetail actions
10. Monitor System — WatcherStatus (health + rules), TxLog, TriggerEngine (toggle)

Each step: description + screenshot placeholder (`![Step N](../images/step-n.png)`) + expected result.

### 繁體中文版

Bottom half: same 10 steps translated to Traditional Chinese.

## 4. Constraints

- British English spelling (colour, initialise, behaviour, etc.)
- Screenshot placeholders only — user replaces with real captures later
- No code changes — documentation only
- Testnet data: Package IDs + Shared Object IDs only (tx digests section omitted)
- Mermaid diagrams for architecture (GitHub-native rendering)
- `docs/images/` directory created with `.gitkeep`

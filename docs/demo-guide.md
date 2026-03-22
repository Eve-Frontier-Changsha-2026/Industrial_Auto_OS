# Demo Walkthrough

> A step-by-step frontend guide for Industrial Auto OS on Sui testnet.
> Covers the full loop: recipes → production → blueprints → marketplace → work orders → monitoring.

---

## Prerequisites

- A **Sui wallet** (Slush or Sui Wallet) connected to **testnet**
- **Testnet SUI** — run `sui client faucet` or visit the [web faucet](https://faucet.sui.io)
- **Node.js** >= 18

## Setup

```bash
cd frontend
npm install
npm run dev
```

Open [http://localhost:5173](http://localhost:5173) in your browser. You should see the Industrial Auto OS HUD dashboard with an amber-themed interface.

> **Note:** Ensure `.env` contains the correct testnet package IDs. See `.env.example` for the template.

---

## Step 1: Connect Wallet

Click the **Connect Wallet** button in the top bar. Select your Sui wallet and approve the connection.

**Expected result:** The top bar displays your truncated wallet address and the network indicator shows "testnet".

![Step 1 — Connect Wallet](../images/step-1.png)

---

## Step 2: Browse Recipes

Open the **RecipeBrowser** pane from the pane menu (top-left "+" button).

Browse the available recipes. You should see **Tritanium Refining** with its input materials, output materials, base duration, and fuel cost.

**Expected result:** A table listing all on-chain recipes with their input/output ratios.

![Step 2 — Recipe Browser](../images/step-2.png)

---

## Step 3: View Production Line

Open the **ProductionMonitor** pane.

You should see **Assembly Line Alpha** (or any production line you have created). The card shows:
- Status (Idle / Producing / Completed)
- Operator address
- Linked recipe
- Material balances

**Expected result:** At least one production line card displayed with its current status.

![Step 3 — Production Monitor](../images/step-3.png)

---

## Step 4: Start Production

On a production line card in the **ProductionMonitor** pane, click **Start**.

Select a Blueprint Original (BPO) to use for this production run. Sign the transaction in your wallet.

**Expected result:** A success toast appears. The production line status changes to **Producing** with a progress indicator.

![Step 4 — Start Production](../images/step-4.png)

---

## Step 5: Complete Production

Once the production duration has elapsed, the **Complete** button becomes available on the production line card.

Click **Complete** and sign the transaction.

**Expected result:** A success toast appears. Output materials are credited to the production line's output balance. Status returns to **Idle**.

![Step 5 — Complete Production](../images/step-5.png)

---

## Step 6: Browse Blueprints

Open the **BlueprintInventory** pane.

This pane displays all BPOs (Blueprint Originals) and BPCs (Blueprint Copies) owned by your wallet. Each entry shows:
- Type (BPO / BPC)
- Efficiency rating and material level
- Runs remaining (unlimited for BPOs)

**Expected result:** A table listing your blueprints with efficiency bars and metadata.

![Step 6 — Blueprint Inventory](../images/step-6.png)

---

## Step 7: List BPO on Marketplace

Open the **MarketListings** pane.

Click **List** on a BPO you own. Set the asking price in SUI and confirm. Sign the transaction.

**Expected result:** A success toast appears. Your BPO now appears in the marketplace listings with the price you set.

![Step 7 — Marketplace Listing](../images/step-7.png)

---

## Step 8: Create Work Order

Open the **WorkOrderCreate** pane.

Fill in:
- **Item type** — the material or product to be produced
- **Quantity** — how many units
- **Reward** — SUI amount offered for completion

Click **Create** and sign the transaction.

**Expected result:** A success toast appears. The work order is created with status **Created** and the reward is held in escrow.

![Step 8 — Create Work Order](../images/step-8.png)

---

## Step 9: View Work Order Board

Open the **WorkOrderBoard** pane.

You should see your newly created work order in the list. Click on it to open the **WorkOrderDetail** view.

The detail view shows:
- Order metadata (item, quantity, reward, deadline)
- Available actions based on status and your role (creator / acceptor)
  - **Accept** (if you are not the creator)
  - **Complete** (if you are the acceptor and goods are ready)
  - **Cancel** (if you are the creator and order is still open)

**Expected result:** The work order board displays all orders; the detail view shows contextual action buttons.

![Step 9 — Work Order Board](../images/step-9.png)

---

## Step 10: Monitor System

Open the following three panes to observe the system's automation layer:

### WatcherStatus
Shows the off-chain watcher's health, uptime, and which rule handlers are currently active.

### TxLog
Displays recent transactions executed by the watcher, with filters by rule type and status (success / failure).

### TriggerEngine
Lists all on-chain trigger rules. You can **toggle** rules on/off or **create** new threshold triggers (e.g. "start production when ore balance exceeds 500").

**Expected result:** All three panes show live data from the watcher's REST API and on-chain state.

![Step 10 — System Monitoring](../images/step-10.png)

---

That's the complete demo loop! You have seen:

1. **Recipe definition** — what can be built
2. **Production execution** — how materials become goods
3. **Blueprint economy** — IP ownership via BPO/BPC NFTs
4. **Marketplace** — trading blueprints for SUI
5. **Work orders** — coordinating production with escrow
6. **Automation** — watcher and trigger engine keeping the factory running

---
---

# 展示指南（繁體中文版）

> Industrial Auto OS 在 Sui 測試網上的前端操作指南。
> 涵蓋完整流程：配方 → 生產 → 藍圖 → 市場 → 工單 → 系統監控。

---

## 前置需求

- **Sui 錢包**（Slush 或 Sui Wallet）已連接至 **testnet**
- **測試網 SUI** — 執行 `sui client faucet` 或至 [網頁水龍頭](https://faucet.sui.io) 領取
- **Node.js** >= 18

## 啟動設定

```bash
cd frontend
npm install
npm run dev
```

在瀏覽器開啟 [http://localhost:5173](http://localhost:5173)。你會看到 Industrial Auto OS 的琥珀色 HUD 主題介面。

> **注意：** 確認 `.env` 檔案包含正確的測試網 Package ID。可參考 `.env.example` 範本。

---

## 步驟 1：連接錢包

點擊頂部列的 **Connect Wallet** 按鈕，選擇你的 Sui 錢包並批准連接。

**預期結果：** 頂部列顯示你的錢包地址（縮寫），網路指示為「testnet」。

![步驟 1 — 連接錢包](../images/step-1.png)

---

## 步驟 2：瀏覽配方

從面板選單（左上角「+」按鈕）開啟 **RecipeBrowser** 面板。

瀏覽可用配方，你會看到 **Tritanium Refining**（三鈦合金精煉），顯示輸入材料、輸出材料、基礎工時與燃料成本。

**預期結果：** 表格列出所有鏈上配方及其輸入/輸出比例。

![步驟 2 — 配方瀏覽器](../images/step-2.png)

---

## 步驟 3：查看產線

開啟 **ProductionMonitor** 面板。

你會看到 **Assembly Line Alpha**（或你已建立的產線）。卡片顯示：
- 狀態（Idle / Producing / Completed）
- 操作員地址
- 綁定配方
- 材料餘額

**預期結果：** 至少一張產線卡片顯示目前狀態。

![步驟 3 — 產線監控](../images/step-3.png)

---

## 步驟 4：啟動生產

在 **ProductionMonitor** 面板的產線卡片上，點擊 **Start**。

選擇一個藍圖原件（BPO）用於此次生產。在錢包中簽署交易。

**預期結果：** 出現成功提示（toast）。產線狀態變為 **Producing**，顯示進度指示。

![步驟 4 — 啟動生產](../images/step-4.png)

---

## 步驟 5：完成生產

生產工時結束後，產線卡片上的 **Complete** 按鈕會變為可用。

點擊 **Complete** 並簽署交易。

**預期結果：** 出現成功提示。產出材料計入產線的輸出餘額。狀態回到 **Idle**。

![步驟 5 — 完成生產](../images/step-5.png)

---

## 步驟 6：瀏覽藍圖

開啟 **BlueprintInventory** 面板。

此面板顯示你錢包擁有的所有 BPO（藍圖原件）和 BPC（藍圖複本）。每筆資料包含：
- 類型（BPO / BPC）
- 效率等級與材料等級
- 剩餘次數（BPO 為無限）

**預期結果：** 表格列出你的藍圖，含效率條與中繼資料。

![步驟 6 — 藍圖庫存](../images/step-6.png)

---

## 步驟 7：在市場上架 BPO

開啟 **MarketListings** 面板。

對你擁有的 BPO 點擊 **List**，設定 SUI 售價並確認。簽署交易。

**預期結果：** 出現成功提示。你的 BPO 出現在市場列表中，顯示你設定的價格。

![步驟 7 — 市場上架](../images/step-7.png)

---

## 步驟 8：建立工單

開啟 **WorkOrderCreate** 面板。

填入：
- **物品類型** — 要生產的材料或產品
- **數量** — 幾個單位
- **獎勵** — 提供的 SUI 金額

點擊 **Create** 並簽署交易。

**預期結果：** 出現成功提示。工單以 **Created** 狀態建立，獎勵進入託管（escrow）。

![步驟 8 — 建立工單](../images/step-8.png)

---

## 步驟 9：查看工單看板

開啟 **WorkOrderBoard** 面板。

你會看到剛建立的工單。點擊它開啟 **WorkOrderDetail** 詳情。

詳情畫面顯示：
- 工單資訊（物品、數量、獎勵、截止時間）
- 依狀態與角色（發佈者 / 接單者）顯示可用操作
  - **Accept**（非發佈者可接單）
  - **Complete**（接單者完成生產後）
  - **Cancel**（發佈者在工單仍開放時取消）

**預期結果：** 工單看板顯示所有工單；詳情畫面顯示情境對應的操作按鈕。

![步驟 9 — 工單看板](../images/step-9.png)

---

## 步驟 10：系統監控

開啟以下三個面板觀察系統自動化層：

### WatcherStatus（監控狀態）
顯示 off-chain watcher 的健康狀態、運行時間，以及目前啟用的規則處理器。

### TxLog（交易日誌）
顯示 watcher 執行的近期交易，可依規則類型與狀態（成功 / 失敗）篩選。

### TriggerEngine（觸發引擎）
列出所有鏈上觸發規則。你可以 **切換** 規則啟用/停用，或 **建立** 新的門檻觸發器（例如「礦石餘額超過 500 時自動啟動生產」）。

**預期結果：** 三個面板皆顯示來自 watcher REST API 與鏈上狀態的即時資料。

![步驟 10 — 系統監控](../images/step-10.png)

---

以上就是完整的展示流程！你已看到：

1. **配方定義** — 能生產什麼
2. **生產執行** — 材料如何變成成品
3. **藍圖經濟** — 透過 BPO/BPC NFT 的 IP 所有權
4. **市場交易** — 用 SUI 交易藍圖
5. **工單系統** — 透過託管協調生產
6. **自動化** — watcher 與觸發引擎維持工廠運轉

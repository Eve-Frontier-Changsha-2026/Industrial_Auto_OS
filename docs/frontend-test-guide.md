# Frontend 使用者情境測試劇本

> Industrial Auto OS — EVE Frontier Integration
> 網路：SUI Testnet
> 自動化測試：36/36 passing (vitest)

---

## 測試前置條件

| 項目 | 需求 |
|------|------|
| 瀏覽器 | Chrome / Firefox / Brave（需 SUI 錢包擴充） |
| 錢包 | Sui Wallet 或 Suiet，切到 **Testnet** |
| 餘額 | ≥ 2 SUI（gas + escrow + 買賣用） |
| 帳號 | **2 個地址**（A = 管理者/發單者，B = 操作員/接單者） |
| 前端 | `http://localhost:5173`（或 Vercel 部署 URL） |
| Watcher | `http://localhost:3001`（測 Watcher 相關 pane 時需要） |

---

## Scenario 1：首次進入 — 連接錢包與認識介面

**角色**：新使用者（地址 A）

### 步驟

1. 開啟瀏覽器，前往前端 URL
2. 畫面應顯示 **EVE Frontier 風格的深色 HUD 介面**，TopBar 在最上方
3. 應看到 **5 個預設 pane**：
   - SystemOverview（系統總覽）
   - ProductionMonitor（生產監控）
   - WorkOrderBoard（工單看板）
   - ActivityFeed（事件流）
   - WatcherStatus（監控狀態）
4. 點擊 TopBar 右上角的 **Connect Wallet** 按鈕
5. 錢包擴充彈出 → 選擇帳號 A → 授權連接
6. TopBar 應顯示截斷地址，例如 `0xa3f1...8c02`
7. 各 pane 應開始載入鏈上資料（看到 loading → data 切換）

### 驗證重點

- [ ] 未連接錢包時，唯讀 pane（SystemOverview、RecipeBrowser）是否能顯示資料
- [ ] 連接後，需要簽名的操作按鈕是否出現（如 Start Production、Create Order）
- [ ] 錢包地址顯示正確且已截斷

---

## Scenario 2：佈局管理 — 拖拉、縮放、記憶

**角色**：帳號 A（已連接）

### 步驟

1. **拖曳** ProductionMonitor 的標題列，移動到畫面右側 → 其他 pane 應自動重排
2. **拉伸** SystemOverview 的右下角，把它放大 → 內容自適應新尺寸
3. 點擊 ActivityFeed 的 **最小化按鈕（—）** → pane 收縮成只剩標題列
4. 點擊 WorkOrderBoard 的 **最大化按鈕（□）** → pane 全螢幕 overlay 覆蓋整個畫面
5. 點擊 overlay 右上角關閉或按 ESC → 回到正常 grid
6. 點擊 WatcherStatus 的 **關閉按鈕（×）** → pane 從 grid 消失
7. 在 TopBar 的 pane 選單中，找到 **RecipeBrowser** → 點擊開啟 → 新 pane 出現在 grid
8. **重新整理瀏覽器（F5）** → 你剛才的佈局變更應完整保留（localStorage）
9. 開啟 DevTools → Application → Local Storage → 找到 key `industrial-auto-os-layout` → 刪除它
10. 重新整理 → 應回到預設 5 pane 佈局

### 驗證重點

- [ ] 拖拉和縮放流暢、無閃爍
- [ ] 最大化 overlay 正確覆蓋，內容完整顯示
- [ ] 關閉的 pane 確實消失，可從選單重新開啟
- [ ] 佈局在重新整理後被正確還原
- [ ] 清除 localStorage 後回到預設狀態

---

## Scenario 3：完整生產流程 — 從配方到產出

**角色**：帳號 A（Production Line owner）

### 前置

- 帳號 A 擁有至少 1 條 ProductionLine 和 1 個 BPO
- 至少存在 1 個 Recipe

### 步驟

1. 開啟 **RecipeBrowser** pane
2. 確認可看到至少 1 個 recipe，記下它的名稱和需要的 input materials
3. 開啟 **ProductionMonitor** pane
4. 找到你的 production line card，應顯示 **IDLE** 狀態
5. 檢查 fuel reserve 數值
6. 如果 fuel 不足，點擊 **Deposit Fuel** → 輸入數量（例如 `1000000000` = 1 SUI）→ 錢包彈出簽名 → 確認
7. 等 toast 顯示成功 → fuel 數值應增加
8. 點擊 **Deposit Materials** → 選擇 recipe 需要的 item type → 輸入數量 → 簽名確認
9. 點擊 **Start Production** → 選擇 recipe 和你的 BPO → 簽名確認
10. toast 成功後，card 狀態應變為 **RUNNING**
11. 等待生產完成（duration 由 recipe 決定，testnet 通常很短）
12. 點擊 **Complete Production** → 簽名確認
13. 狀態回到 **IDLE**，jobs completed +1
14. 點擊 **Withdraw Output** → 選擇產出 item type → 輸入數量 → 簽名確認
15. 切到 **ActivityFeed** pane → 應看到 `ProductionStarted` 和 `ProductionCompleted` 事件

### 驗證重點

- [ ] Fuel deposit 後數值即時更新（5 秒內）
- [ ] Start Production 後狀態從 IDLE → RUNNING
- [ ] Complete Production 後狀態從 RUNNING → IDLE，jobs +1
- [ ] ActivityFeed 顯示對應事件，時間正確
- [ ] 每個操作的 toast 都正常顯示（成功 = 綠色）

---

## Scenario 4：操作員授權 — 多人協作

**角色**：帳號 A（owner）→ 帳號 B（operator）

### 步驟

1. **帳號 A** 開啟 ProductionMonitor
2. 在自己的 line card 上，點擊 **Authorize Operator**
3. 輸入帳號 B 的完整地址 → 簽名確認
4. Operators 列表應顯示帳號 B 的地址
5. **切換到帳號 B**（切錢包帳號或開新瀏覽器）
6. 帳號 B 開啟 ProductionMonitor → 應能看到同一條 line
7. 帳號 B 嘗試 **Start Production** → 應成功（因為是 authorized operator）
8. 帳號 B 嘗試 **Deposit Fuel** → 應成功
9. **切回帳號 A** → 點擊 **Revoke Operator** → 移除帳號 B
10. **帳號 B** 再嘗試操作 → 應失敗，toast 顯示 error（not authorized operator）

### 驗證重點

- [ ] 授權後 operator 列表更新
- [ ] Operator 可執行 start/deposit/complete 操作
- [ ] Revoke 後 operator 操作被拒絕
- [ ] 錯誤 toast 顯示可讀的錯誤訊息（非 raw abort code）

---

## Scenario 5：藍圖管理 — Mint BPC 與效率查看

**角色**：帳號 A（BPO owner）

### 步驟

1. 開啟 **BlueprintInventory** pane
2. 應看到 **BPO** 區塊，列出你擁有的 Blueprint Originals
3. 每個 BPO 應顯示：recipe 關聯、efficiency（效率條）、已 mint 的 BPC 數量
4. 開啟 **BlueprintMint** pane
5. 選擇一個 BPO → 輸入 uses 數量（例如 `5`）→ 點擊 Mint → 簽名
6. toast 成功後，切回 BlueprintInventory
7. **BPC** 區塊應出現新的 Blueprint Copy，顯示 remaining uses = 5
8. 嘗試輸入 uses = `0` → 前端應阻擋或 tx 失敗

### 驗證重點

- [ ] BPO 和 BPC 分區清楚
- [ ] Efficiency bar 視覺化正確
- [ ] Mint 後 BPC 即時出現（10 秒 refetch）
- [ ] 無效輸入被正確處理

---

## Scenario 6：工單全生命週期 — 從發單到完成

**角色**：帳號 A（issuer）→ 帳號 B（acceptor）

### Step 1：帳號 A 發單

1. 帳號 A 開啟 **WorkOrderCreate** pane
2. 填寫表單：
   - Description：`Test order - 100 units`
   - Recipe：選擇一個 recipe
   - Quantity：`100`
   - Deadline：選擇未來 7 天的時間
   - Priority：`High`
   - Escrow：`500000000`（0.5 SUI）
3. 點擊 Create → 錢包簽名（會從餘額扣 0.5 SUI escrow）
4. toast 成功
5. 切到 **WorkOrderBoard** → 應看到新 order，狀態 = **OPEN**，Priority = High

### Step 2：帳號 B 接單

6. **切換到帳號 B**
7. 開啟 WorkOrderBoard → 找到剛才的 order
8. 點擊該 order → 跳到 **WorkOrderDetail**
9. 應顯示完整資訊：issuer = 帳號 A、quantity = 100、escrow = 0.5 SUI、deadline
10. 點擊 **Accept** → 簽名 → 狀態變 **ACCEPTED**

### Step 3：帳號 B 交貨

11. 在 WorkOrderDetail 中，點擊 **Deliver**
12. 選擇 item type → 輸入 quantity = `50`（部分交貨）→ 簽名
13. delivered 應更新為 50/100
14. 再次 Deliver → quantity = `50` → 簽名
15. delivered = 100/100 → 狀態應變 **DELIVERED**

### Step 4：帳號 A 確認完成

16. **切回帳號 A**
17. 開啟 WorkOrderDetail → 狀態 = DELIVERED
18. 點擊 **Complete** → 簽名
19. 狀態變 **COMPLETED**
20. 帳號 B 的餘額應收到 escrow（0.5 SUI 扣除 gas）

### Step 5：驗證事件

21. 開啟 **ActivityFeed** → 應看到：
    - WorkOrderCreated
    - WorkOrderAccepted
    - WorkOrderDelivered（×2）
    - WorkOrderCompleted

### 驗證重點

- [ ] Escrow 從帳號 A 餘額扣除
- [ ] 部分交貨 delivered 數量正確累加
- [ ] 只有 issuer 能 Complete，只有 acceptor 能 Deliver
- [ ] 完成後 escrow 釋放給 acceptor
- [ ] 所有狀態轉換在 Board 和 Detail 即時反映

---

## Scenario 7：工單取消與過期

**角色**：帳號 A（issuer）

### 7a：主動取消

1. 帳號 A 建立新 order（同 Scenario 6 Step 1）
2. 在 WorkOrderDetail 中，點擊 **Cancel**（OPEN 狀態才能取消）
3. 簽名 → 狀態變 CANCELLED
4. Escrow 應退回帳號 A

### 7b：過期取消

1. 建立一個 deadline 極短（例如 5 分鐘後）的 order
2. 等待 deadline 過期
3. **任何人**（帳號 A 或 B）都可以點擊 **Cancel Expired**
4. 簽名 → 狀態變 CANCELLED，escrow 退回 issuer

### 驗證重點

- [ ] OPEN 狀態可取消，ACCEPTED 狀態不可取消
- [ ] Cancel 後 escrow 確實退回（查看餘額）
- [ ] 過期 order 任何人可觸發取消

---

## Scenario 8：藍圖市場交易 — 上架、購買、下架

**角色**：帳號 A（賣家）→ 帳號 B（買家）

### Step 1：帳號 A 上架 BPO

1. 帳號 A 開啟 **MarketListings** pane
2. 點擊 **List BPO**
3. 選擇一個 BPO → 輸入 price = `100000000`（0.1 SUI）→ 簽名
4. 該 BPO 應從 BlueprintInventory 消失
5. MarketListings 應顯示新的 listing

### Step 2：帳號 B 購買

6. **切到帳號 B** → 開啟 MarketListings
7. 找到帳號 A 的 listing → 點擊 **Buy**
8. 錢包彈出，確認支付 0.1 SUI → 簽名
9. toast 成功 → listing 從市場消失
10. 帳號 B 開啟 BlueprintInventory → 應看到購買的 BPO

### Step 3：帳號 A 下架（測試另一個 listing）

11. 帳號 A 再上架一個 BPO（或 BPC）
12. 在 MarketListings 中找到自己的 listing → 點擊 **Delist**
13. 簽名 → BPO 回到 BlueprintInventory

### 異常測試

14. 帳號 B 嘗試 delist 帳號 A 的 listing → 應失敗（not the seller）
15. 帳號 B 嘗試以 0 SUI 購買 → 應失敗（insufficient payment）

### 驗證重點

- [ ] 上架後 BPO/BPC 從 inventory 移出
- [ ] 購買後 BPO/BPC 轉入買家 inventory
- [ ] 交易金額正確（扣除 fee，最低 1 MIST）
- [ ] 只有賣家能 delist
- [ ] BPC 的交易流程與 BPO 相同

---

## Scenario 9：租賃流程 — 出租 BPO 生產

**角色**：帳號 A（lessor）→ 帳號 B（lessee）

### Step 1：帳號 A 建立租約

1. 帳號 A 開啟 **LeaseManager** pane
2. 點擊 **Create Lease**
3. 選擇 BPO → 輸入：
   - Lessee address：帳號 B 地址
   - Deposit：`200000000`（0.2 SUI）
   - Daily rate：`10000000`（0.01 SUI/天）
   - Expiry：7 天後的 timestamp
4. 簽名 → 租約建立

### Step 2：帳號 B 使用租約生產

5. **切到帳號 B** → 開啟 LeaseManager → 應看到 lessee 視角的租約
6. 確認：BPO info、到期日、daily rate、deposit
7. 帳號 B 開啟 ProductionMonitor → 點擊 **Start Production with Lease**
8. 選擇 lease + production line + recipe → 簽名
9. 生產啟動（使用租借的 BPO）

### Step 3：帳號 B 歸還租約

10. 帳號 B 在 LeaseManager 點擊 **Return Lease** → 簽名
11. BPO 回到帳號 A，deposit 退回帳號 B（扣除已使用天數 × daily rate）

### 異常測試

12. 建立一個 expiry 極短的 lease → 等過期
13. 過期後 → 帳號 B 嘗試 Start Production with Lease → 應失敗，toast 顯示 "Lease expired"（code 304）
14. 帳號 A（或任何人）點擊 **Forfeit** → deposit 歸 lessor

### 驗證重點

- [ ] Lessee 可用租借的 BPO 啟動生產
- [ ] Return 後 deposit 根據使用天數計算退款
- [ ] 過期後生產被拒絕（code 304）
- [ ] Forfeit 後 deposit 歸 lessor

---

## Scenario 10：觸發器自動化

**角色**：帳號 A（line owner）+ Watcher 運行中

### 步驟

1. 確認 Watcher 正在運行（終端或 WatcherStatus pane 顯示 OK）
2. 開啟 **TriggerEngine** pane
3. 點擊 **Create Trigger Rule**：
   - Production Line：選你的 line
   - Condition：`INVENTORY_BELOW`
   - Threshold：`50`
   - Target Item Type ID：某個 material 的 type ID
   - Auto Repeat：勾選
   - Cooldown：`60000`（60 秒）
4. 簽名 → 新 rule 出現在列表，enabled = true
5. 點擊 **Toggle** → 停用 → enabled = false
6. 再次 Toggle → 啟用
7. 開啟 **WatcherStatus** → 確認 rule 清單有更新
8. 當 inventory 低於 50 時，Watcher 應自動觸發對應操作
9. 開啟 **TxLog** pane → 應看到 Watcher 自動執行的交易記錄

### 驗證重點

- [ ] Trigger rule 建立後即時出現（5 秒 refetch）
- [ ] Toggle 開關狀態正確反映
- [ ] Watcher 條件滿足時自動執行（查 TxLog）
- [ ] Cooldown 期間不重複觸發

---

## Scenario 11：EVE Frontier 整合 — Item Mapping 與 Access Pass

**角色**：帳號 A（admin，持有 RegistryAdminCap）

### 11a：Item Mapping（需 admin）

1. 開啟 **ItemMapping** pane
2. 點擊 **Add Global Mapping**
3. 輸入 EVE Type ID（例如 `34` = Tritanium）和 Material ID → 簽名
4. Mapping 列表應顯示新項目
5. 嘗試用相同 EVE Type ID 再次新增 → 應失敗（duplicate mapping，code 1003）
6. 點擊 **Remove Global Mapping** → 選擇剛建的 mapping → 簽名 → 移除

### 11b：Factory Access（需 BPO/Lease/WO）

7. 開啟 **GateAccess** pane
8. 點擊 **Claim from Blueprint** → 選 BPO + production line → 簽名
9. 應取得 AccessPass（type = BLUEPRINT）
10. 嘗試再次 claim 同一條 line → 應失敗（already has pass，code 2003）
11. 點擊 **Surrender Pass** → 簽名 → pass 消失
12. 再次 claim → 應成功（因為已 surrender）

### 11c：Placeholder Panes

13. 開啟 **SSUInventory** → 應顯示 placeholder 內容，不 crash
14. 開啟 **LinkAssembly** → 應顯示 placeholder 內容，不 crash

### 驗證重點

- [ ] 非 admin 操作 mapping → 失敗（code 1001）
- [ ] 重複 mapping 被拒絕
- [ ] Claim/Surrender 循環可正常運作
- [ ] Placeholder panes 不 crash

---

## Scenario 12：Watcher 監控

**角色**：帳號 A + Watcher 運行中

### 12a：健康狀態

1. 開啟 **WatcherStatus** pane
2. 應顯示：
   - Health = **OK**（綠色 badge）
   - Uptime 持續遞增
   - Last poll 時間近幾秒內
3. Rule 列表顯示 5 個 rules 及各自的 enabled 狀態

### 12b：交易紀錄

4. 開啟 **TxLog** pane
5. 應顯示 watcher 歷史交易，每筆包含：
   - Rule name（哪個 rule 觸發的）
   - Tx digest（鏈上交易 hash）
   - Status（success / fail）
   - Gas used
   - Timestamp
6. 使用 **Filter by status** → 選 `success` → 只顯示成功 tx
7. 使用 **Filter by rule** → 選某 rule → 只顯示該 rule 的 tx
8. 調整 **Limit** → 控制顯示筆數

### 12c：Watcher 離線

9. 關閉 Watcher 程序
10. 回到 WatcherStatus → Health 應變成 **error/offline**
11. TxLog 應顯示 fetch error 或空列表
12. 確認頁面不 crash
13. 重啟 Watcher → 資料恢復

### 驗證重點

- [ ] Watcher 在線時 health OK，離線時 error
- [ ] TxLog 篩選功能正常
- [ ] Watcher 離線不影響其他 pane 的鏈上操作

---

## Scenario 13：錯誤處理與邊界測試

### 13a：錢包未連接

| 操作 | 預期 |
|------|------|
| 不連接錢包 → 查看 SystemOverview | 正常顯示（唯讀） |
| 不連接錢包 → 查看 RecipeBrowser | 正常顯示（唯讀） |
| 不連接錢包 → 嘗試 Start Production | 按鈕 disabled 或提示連接錢包 |
| 不連接錢包 → 嘗試 Create Order | 按鈕 disabled 或提示連接錢包 |

### 13b：權限錯誤

| 操作 | 預期 Toast |
|------|-----------|
| 非 owner 操作 production line | Error: Not the production line owner |
| 非 operator 嘗試 start production | Error: Not an authorized operator |
| 非 BPO owner 嘗試 mint | Error: Not the blueprint owner |
| 非 issuer 嘗試 cancel order | Error: Status mismatch 或 not issuer |
| 非 seller 嘗試 delist | Error: Not the seller |
| 非 lessee 嘗試 return lease | Error 相關訊息 |
| 非 admin 嘗試 add mapping | Error: Not authorized |

### 13c：極端輸入

| 輸入 | 在哪裡 | 預期 |
|------|--------|------|
| Escrow = `0` | WorkOrderCreate | 前端驗證拒絕或 tx 失敗 |
| Escrow = `-1` | WorkOrderCreate | 前端拒絕輸入 |
| Escrow = `99999999999999999999` | WorkOrderCreate | tx 失敗（餘額不足） |
| Quantity = `0.5` | Deliver | 前端拒絕（Move 只接受整數） |
| Address = `0x123`（不完整） | Authorize Operator | 前端驗證失敗 |
| Deadline = 過去時間 | WorkOrderCreate | 前端驗證或 tx 失敗 |
| Uses = `0` | BlueprintMint | 前端驗證或 tx 失敗 |

### 13d：網路異常

1. 斷開網路（DevTools → Network → Offline）
2. 嘗試操作任意 pane → 應顯示 error 狀態，不 crash
3. 恢復網路 → React Query 自動 refetch → 資料恢復

### 驗證重點

- [ ] 所有錯誤都走 toast，不會出現 unhandled exception
- [ ] Error message 是人類可讀的（不是 raw abort code）
- [ ] 極端輸入不會 crash 前端
- [ ] 網路斷線 → 恢復後自動 recover

---

## Scenario 14：多 Pane 同時操作與資料一致性

### 步驟

1. 同時開啟：ProductionMonitor + SystemOverview + ActivityFeed
2. 在 ProductionMonitor 中 Start Production → 簽名
3. 觀察：
   - SystemOverview 的 Active Jobs 是否 +1（5 秒內）
   - ActivityFeed 是否出現 ProductionStarted 事件（3 秒內）
4. Complete Production → 觀察所有 pane 同步更新
5. 同時開啟：MarketListings + BlueprintInventory
6. List 一個 BPO → 觀察：
   - MarketListings 出現新 listing
   - BlueprintInventory 的 BPO 消失
7. 開啟所有 20 個 panes → 頁面是否仍然可操作（不卡頓）

### 驗證重點

- [ ] 跨 pane 資料一致（同一個操作反映在多個 pane）
- [ ] Refetch 間隔合理（3-30 秒不等）
- [ ] 20 panes 同時不會 crash 或嚴重卡頓

---

## Scenario 15：Demo 展示流程（Hackathon 用）

> 這是完整的 demo 順序，適合 5-10 分鐘展示

### Phase A：介紹（1 分鐘）

1. 顯示預設介面 → 說明 HUD 風格設計
2. 連接錢包
3. 拖拉一個 pane 展示佈局系統

### Phase B：生產系統（3 分鐘）

4. RecipeBrowser → 展示配方
5. ProductionMonitor → Deposit Fuel → Start Production
6. 等待 → Complete Production → Withdraw Output
7. SystemOverview → 指出 stats 更新
8. ActivityFeed → 指出事件流

### Phase C：工單系統（2 分鐘）

9. WorkOrderCreate → 建立高優先級 order（含 escrow）
10. WorkOrderBoard → 篩選 → 找到 order
11. （切帳號）Accept → Deliver → Complete
12. 指出 escrow 自動釋放

### Phase D：市場（1 分鐘）

13. MarketListings → List BPO → 展示上架
14. （切帳號）Buy → 展示購買

### Phase E：EVE Integration（1 分鐘）

15. ItemMapping → Add mapping → 展示 EVE 物品映射
16. GateAccess → Claim from Blueprint → 展示 access pass

### Phase F：自動化（1 分鐘）

17. TriggerEngine → Create rule → 展示觸發器
18. WatcherStatus → 展示健康狀態
19. TxLog → 展示自動執行紀錄

---

## 測試結果記錄表

| Scenario | 描述 | 通過 | 備註 |
|----------|------|------|------|
| 1 | 連接錢包與介面 | | |
| 2 | 佈局管理 | | |
| 3 | 完整生產流程 | | |
| 4 | 操作員授權 | | |
| 5 | 藍圖管理 | | |
| 6 | 工單全生命週期 | | |
| 7 | 工單取消與過期 | | |
| 8 | 市場交易 | | |
| 9 | 租賃流程 | | |
| 10 | 觸發器自動化 | | |
| 11 | EVE 整合 | | |
| 12 | Watcher 監控 | | |
| 13 | 錯誤處理與邊界 | | |
| 14 | 多 Pane 同時操作 | | |
| 15 | Demo 展示流程 | | |

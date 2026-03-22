# 專案名稱：Industrial_Auto_OS (星際工業自動化排程作業系統)

> 📜 **[EVE Frontier 專案憲法與開發準則](https://github.com/Eve-Frontier-Changsha-2026/Constitution/blob/master/EVE_Frontier_Project_Constitution.md)**
> 本專案的世界觀設定與底層相依資源，均遵從此憲法文檔之規範。


## 📌 概念簡介
專為喜愛「採集、建設、生產」的軍工複合體玩家/公會所設計的管理工具，將基地變成「可程式化工廠」。利用 Sui 的可組合性 (Composability)，將輸入原料、排程加工、入庫、轉運自動化，同時提供玩家自定義「生產配方 (recipe)」與觸發條件（例如礦物過半自動精煉）。

## 🎯 解決痛點與核心循環
- **一條龍生產供應鏈**：從礦工傾倒原料入口，OS 自動分流，負責精煉、零件到船隻 / 砲塔鑄造，完美契合「收集 → 鑄造」循環。
- **工單系統與代幣結算**：聯盟能發布生產任務，讓後勤玩家根據訂單工作，並透過 Sui 代幣完成結算。
- **戰損與能源連動**：系統記錄前線戰損，自動調整生產線補充艦船或彈藥，同時追蹤能耗波動與燃料網路 (AstroLogistics) 動態整合。

## 🔗 與 Sui / World Contracts 的結合
- 每條產線、每個 recipe、每個工單都是獨立的 Sui 物件，可被轉移、租賃，或打包作「藍圖 NFT」販售給其他玩家。
- World Contracts 用於描述「配方」與「工序圖」，允許組合、繼承與擴展，形成複雜有趣的工業模組生態系。
- 對外提供 API，使外部工具能分析運作效率，甚至給出投資回報 (ROI) 與瓶頸優化建議。

## 🏆 得獎潛力
- **切中長尾需求**：工業是 EVE 類遊戲最龐大的經濟基礎內容，官方非常重視玩家驅動經濟。
- **強大的技術展示**：把「編程」具象化成工業流程，展現出 Smart Assemblies + Sui Move 模型可組合性的最大威力。
- **商業長期價值**：出售高效率產線藍圖與代營運工業基地，能建立穩固的經濟地位與龐大交易量。


## Specifications

### 2026 03 20 Industrial Auto Os Design

# Industrial Auto OS — System Architecture & Spec

> 星際工業自動化排程作業系統
> Date: 2026-03-20
> Status: Reviewed (post sui-dev-agents audit)
> Scope: Full-function Demo (Phase 3)
> Reviews: architect, security-guard, red-team, developer, frontend

---

## 1. Overview

Industrial Auto OS 是 EVE Frontier 生態系中的「工業後勤核心」，將基地變成可程式化工廠。系統涵蓋：原料輸入 → 配方排程 → 自動補產 → 成品交付 → 藍圖 IP 經濟。

### 定位

- **上游**：AstroLogistics（燃料/物流）、Wreckage Insurance（殘骸回收原料）
- **下游**：Fleet Command（戰損補產工單）
- **獨立**：藍圖 NFT 市場（BPO/BPC 買賣租賃）

### 核心循環

```
前線戰損 → 觸發引擎偵測 → 自動啟動產線 → 成品入庫 → 工單交付 → 前線補充 → 再戰損（循環）
```

---

## 2. Design Decisions

| 問題 | 決策 | 理由 |
|---|---|---|
| MVP 範圍 | 全功能 Demo | 展示完整軍工經濟閉環 |
| Recipe 模型 | 混合：鏈上單層，off-chain DAG 編排 | Sui gas 限制不適合鏈上遞迴 DAG |
| 觸發引擎 | 混合：鏈上規則 + off-chain watcher + 鏈上驗證 | Watcher 保 liveness，鏈上保 safety |
| 藍圖 NFT | BPO/BPC 分層授權 | 最接近 EVE 原生工業體驗，IP 經濟模型最豐富 |
| 結算代幣 | 純 SUI（不做泛型） | 簡化實作，Balance\<SUI\> 不支援 store |
| 跨專案整合 | Fleet Command 戰損線真實整合，其餘 mock | 一條真實閉環 > 三條 mock 閉環 |
| ProductionLine 所有權 | **Shared Object** | Operator/watcher 需傳入 &mut，owned object 不允許非 owner 操作 |
| LeaseAgreement 所有權 | **Shared Object** | Lessor 需在 lessee 消失時 forfeit，owned by lessee 會永久鎖死 BPO |
| Module 可見性 | **public(package)** 取代 friend | Move 2024 慣例，friend 已棄用 |

---

## 3. Architecture: Core + Satellite Pattern

```
packages/
├── industrial_core/    核心 Package
│   ├── recipe.move              配方定義
│   ├── blueprint.move           BPO/BPC 藍圖
│   ├── production_line.move     產線管理
│   ├── trigger_engine.move      觸發規則與執行
│   └── mock_fuel.move           Mock 燃料（#[test_only] 或 demo 標記）
│
├── work_order/         衛星 Package: 工單系統
│   ├── work_order.move          工單生命週期 + Escrow
│   └── fleet_integration.move   Fleet Command 戰損橋接
│
└── marketplace/        衛星 Package: 藍圖市場
    ├── marketplace.move         上架/購買/手續費
    └── lease.move               BPO 租賃
```

**拆分原則**：不會變的放一起（產線、配方 = 物理定律），會變的拆出去（市場、工單 = 商業規則）。

### 函式可見性分類

| 類型 | 用途 | 誰能呼叫 |
|---|---|---|
| `public(package) fun` | 模組間內部呼叫 | 同 package 內其他 module（取代 friend） |
| `public fun` | 衛星 package 或 PTB 中間步驟 | 任何 package，可在 PTB 中鏈式呼叫 |
| `public entry fun` | PTB 終端呼叫或獨立 tx | 任何 package，作為 tx 入口 |

關鍵區分：
- `start_production`, `complete_production`, `execute_trigger` → `public fun`（需在 PTB 中組合）
- `create_recipe`, `create_production_line` → `entry fun`（獨立操作）
- `evaluate_trigger` → `public fun`（純讀取，可在 PTB 中呼叫不寫狀態）

### 依賴圖

```
work_order ──→ industrial_core  (需要 ProductionLine, DamageReport)
marketplace ──→ industrial_core (需要 BlueprintOriginal, BlueprintCopy)
work_order ⊥ marketplace        (無依賴 ✓)
```

---

## 4. Data Model

### 4.0 Material Representation (全域共用)

```move
// Bag 使用慣例：
//   key:   u32 (item_type_id)
//   value: u64 (quantity)
//
// deposit_materials 驗證 item_type_id 必須存在於綁定 recipe 的 inputs 中
// 防止 Bag key pollution（任意 item_type_id 灌入）
//
// evaluate_trigger 讀取 Bag 時：
//   if (!bag::contains(&buffer, item_type_id)) → treat as quantity = 0
//   不會因 missing key 而 abort
```

### 4.1 industrial_core

#### Recipe

```move
public struct Recipe has key, store {
    id: UID,
    name: String,
    inputs: vector<MaterialRequirement>,  // 必須 non-empty
    output: MaterialOutput,               // quantity 必須 > 0
    base_duration_ms: u64,                // 必須 > 0
    energy_cost: u64,                     // 必須 > 0
    creator: address,
}

public struct MaterialRequirement has store, copy, drop {
    item_type_id: u32,
    quantity: u64,    // 必須 > 0
}

public struct MaterialOutput has store, copy, drop {
    item_type_id: u32,
    quantity: u64,    // 必須 > 0
}
```

#### Blueprint (BPO / BPC)

```move
public struct BlueprintOriginal has key, store {
    id: UID,
    recipe_id: ID,
    copies_minted: u64,
    max_copies: u64,              // 0 = unlimited
    material_efficiency: u8,      // 0-25
    time_efficiency: u8,          // 0-25
}
// 無 owner 欄位。BPO 是 owned object，Sui runtime 追蹤所有權。
// mint_bpc 需要 &mut BPO → 只有 owner 能呼叫。
// 若 BPO 被 wrap 進 LeaseAgreement/BpoListing，外部無法取得 &mut。

public struct BlueprintCopy has key, store {
    id: UID,
    recipe_id: ID,
    source_bpo_id: ID,
    uses_remaining: u64,
    material_efficiency: u8,
    time_efficiency: u8,
}
```

**效率公式（ceiling division + u128 中間運算）**：
```move
// 防止 u64 溢位 + 防止小數量歸零
let actual_qty = (((base_qty as u128) * ((100 - me as u128)) + 99) / 100) as u64;
assert!(actual_qty >= 1, E_ZERO_MATERIAL_AFTER_EFFICIENCY);

let actual_duration = (((base_duration as u128) * ((100 - te as u128)) + 99) / 100) as u64;
```

#### ProductionLine (Shared Object)

```move
public struct ProductionLine has key {
    id: UID,
    name: String,
    owner: address,
    authorized_operators: VecSet<address>,  // 最多 10 個，用 VecSet 去重
    recipe_id: ID,                          // 綁定配方（建立時設定）
    input_buffer: Bag,                      // key=u32, value=u64
    output_buffer: Bag,
    fuel_reserve: u64,
    status: u8,                             // STATUS_IDLE=0, STATUS_RUNNING=1, STATUS_PAUSED=2
    current_job_start: u64,
    current_job_end: u64,
    jobs_completed: u64,
}
// Shared Object: transfer::share_object(line) in create_production_line
// 所有 mutating function 必須檢查 require_owner(ctx) 或 require_owner_or_operator(ctx)

const MAX_OPERATORS: u64 = 10;
const STATUS_IDLE: u8 = 0;
const STATUS_RUNNING: u8 = 1;
const STATUS_PAUSED: u8 = 2;
```

**權限矩陣**：

| 函式 | Owner | Operator | Anyone |
|---|---|---|---|
| authorize_operator | ✅ | ❌ | ❌ |
| revoke_operator | ✅ | ❌ | ❌ |
| deposit_materials | ✅ | ❌ | ❌ |
| deposit_fuel | ✅ | ❌ | ❌ |
| start_production | ✅ | ✅ | ❌ |
| complete_production | ✅ | ✅ | ❌ |
| withdraw_output | ✅ | ❌ | ❌ |

#### TriggerRule

```move
public struct TriggerRule has key {
    id: UID,
    production_line_id: ID,
    condition_type: u8,           // 0=inventory_below, 1=external_event, 2=schedule
    threshold: u64,
    target_item_type_id: u32,
    auto_repeat: bool,
    enabled: bool,
    last_triggered: u64,
    cooldown_ms: u64,
}
// 移除 store：TriggerRule 不需要被 wrap 或轉移
// 創建時必須傳入 &ProductionLine 並驗證 sender == owner
```

#### Events

```move
public struct ProductionStartedEvent has copy, drop {
    production_line_id: ID,
    recipe_id: ID,
    operator: address,            // 誰觸發的
    estimated_completion: u64,    // timestamp
}

public struct ProductionCompletedEvent has copy, drop {
    production_line_id: ID,
    output_item_type_id: u32,
    output_quantity: u64,
    timestamp: u64,               // Clock timestamp
    jobs_completed: u64,          // running total
}

public struct TriggerFiredEvent has copy, drop {
    trigger_rule_id: ID,
    production_line_id: ID,
    condition_type: u8,
    timestamp: u64,
}
```

### 4.2 work_order

```move
public struct WorkOrder has key {
    id: UID,
    issuer: address,
    item_type_id: u32,
    quantity_requested: u64,
    quantity_delivered: u64,
    escrow_balance: Balance<SUI>,
    deadline: u64,                          // 上限 MAX_DEADLINE = 30 days from creation
    priority: u8,                           // 0=normal, 1=urgent, 2=critical
    status: u8,
    acceptor: Option<address>,
    source_event: Option<DamageReport>,
    delivered_at: Option<u64>,              // 首次滿額交付的 timestamp
}
// 無 store：Balance<SUI> 阻止。WorkOrder 作為 shared object 供雙方互動。

const STATUS_OPEN: u8 = 0;
const STATUS_ACCEPTED: u8 = 1;
const STATUS_IN_PROGRESS: u8 = 2;
const STATUS_DELIVERED: u8 = 3;
const STATUS_COMPLETED: u8 = 4;
const STATUS_CANCELLED: u8 = 5;

const MAX_DEADLINE_MS: u64 = 30 * 24 * 60 * 60 * 1000; // 30 days
const MIN_ESCROW: u64 = 100_000_000; // 0.1 SUI
const AUTO_COMPLETE_GRACE_MS: u64 = 72 * 60 * 60 * 1000; // 72h

public struct DamageReport has store, copy, drop {
    fleet_command_event_id: ID,
    lost_ship_type_id: u32,
    lost_quantity: u64,
    battle_location: u64,
    timestamp: u64,
}

public struct WorkOrderBoard has key {
    id: UID,
    active_orders: Table<ID, bool>,     // 替代 vector<ID>，O(1) insert/remove
    total_orders_created: u64,
    total_value_settled: u64,
    extension: Bag,                     // 未來欄位擴展用
}

// Events
public struct WorkOrderCreatedEvent has copy, drop {
    order_id: ID,
    issuer: address,
    item_type_id: u32,
    quantity: u64,
    escrow_amount: u64,
    deadline: u64,
    priority: u8,
}

public struct WorkOrderAcceptedEvent has copy, drop {
    order_id: ID,
    acceptor: address,
}

public struct WorkOrderCompletedEvent has copy, drop {
    order_id: ID,
    acceptor: address,
    item_type_id: u32,
    quantity_delivered: u64,
    settled_amount: u64,
}

public struct WorkOrderCancelledEvent has copy, drop {
    order_id: ID,
    reason: u8,     // 0=issuer_cancel, 1=expired, 2=auto_complete
}
```

### 4.3 marketplace

```move
public struct Marketplace has key {
    id: UID,
    fee_bps: u64,                 // basis points (250 = 2.5%)
    fee_collector: Balance<SUI>,
    total_listings: u64,
    total_volume: u64,
    extension: Bag,               // 未來擴展
}

/// Admin 能力物件（取代 admin: address，可轉移）
public struct MarketplaceAdminCap has key, store {
    id: UID,
}

const MIN_LISTING_PRICE: u64 = 10_000_000; // 0.01 SUI

/// BPO 上架
public struct BpoListing has key, store {
    id: UID,
    seller: address,
    bpo: BlueprintOriginal,       // 實際 BPO 託管
    recipe_id: ID,
    price: u64,
    listed_at: u64,
    material_efficiency: u8,
    time_efficiency: u8,
}

/// BPC 上架
public struct BpcListing has key, store {
    id: UID,
    seller: address,
    bpc: BlueprintCopy,
    recipe_id: ID,
    price: u64,
    listed_at: u64,
    uses_remaining: u64,
    material_efficiency: u8,
    time_efficiency: u8,
}

/// 租賃合約 (Shared Object)
public struct LeaseAgreement has key {
    id: UID,
    bpo: BlueprintOriginal,       // BPO 實體託管
    lessor: address,
    lessee: address,
    lease_fee: u64,
    deposit: Balance<SUI>,
    start_time: u64,
    duration_ms: u64,
}
// 無 store：Balance<SUI> 阻止。
// Shared Object：lessor 可 forfeit，lessee 可 return。

// Events
public struct BpoListedEvent has copy, drop {
    listing_id: ID,
    seller: address,
    recipe_id: ID,
    price: u64,
}

public struct BlueprintPurchasedEvent has copy, drop {
    listing_id: ID,
    buyer: address,
    seller: address,
    price: u64,
    fee: u64,
}

public struct LeaseCreatedEvent has copy, drop {
    lease_id: ID,
    lessor: address,
    lessee: address,
    bpo_id: ID,
    duration_ms: u64,
}

public struct LeaseReturnedEvent has copy, drop {
    lease_id: ID,
    returned_by: address,   // lessee or lessor (forfeit)
}
```

### 4.4 Package Initialization

```move
// industrial_core::init — 無 shared object

// work_order::init
fun init(ctx: &mut TxContext) {
    let board = WorkOrderBoard {
        id: object::new(ctx),
        active_orders: table::new(ctx),
        total_orders_created: 0,
        total_value_settled: 0,
        extension: bag::new(ctx),
    };
    transfer::share_object(board);
}

// marketplace::init
fun init(ctx: &mut TxContext) {
    let admin_cap = MarketplaceAdminCap { id: object::new(ctx) };
    transfer::transfer(admin_cap, tx_context::sender(ctx));  // admin 持有 cap

    let market = Marketplace {
        id: object::new(ctx),
        fee_bps: 250,
        fee_collector: balance::zero(),
        total_listings: 0,
        total_volume: 0,
        extension: bag::new(ctx),
    };
    transfer::share_object(market);
}
```

---

## 5. Core Functions

### 5.1 industrial_core

```
// === Recipe ===
entry fun create_recipe(name, inputs, output, duration, energy_cost, ctx) → Recipe
    // assert vector::length(&inputs) > 0
    // assert each input.quantity > 0
    // assert output.quantity > 0
    // assert duration > 0
    // assert energy_cost > 0

// === Blueprint ===
entry fun mint_bpo(recipe: &Recipe, max_copies, me: u8, te: u8, ctx) → BlueprintOriginal
    // assert me <= 25 && te <= 25

public fun mint_bpc(bpo: &mut BlueprintOriginal, uses: u64, ctx) → BlueprintCopy
    // 需要 &mut BPO → 只有 owner 能呼叫（wrap 在 Lease/Listing 時外部無法取得 &mut）
    // bpo.copies_minted += 1
    // assert max_copies == 0 || copies_minted <= max_copies

public fun use_and_destroy_bpc(bpc: BlueprintCopy) → (ID, u8, u8)
    // 原子操作：decrement uses_remaining
    // 若 uses_remaining == 0 → 自動 delete(bpc)，回傳 efficiency 值
    // 若 > 0 → 需回傳 bpc 給 caller（設計為消耗型：每次呼叫消耗 1 use）
    // 改用: use_bpc(bpc: BlueprintCopy) → (BlueprintCopy 或銷毀, ID, u8, u8)
    // 實際實作建議：
    //   public fun use_bpc(bpc: &mut BlueprintCopy): (ID, u8, u8)  // decrement
    //   public fun destroy_empty_bpc(bpc: BlueprintCopy)            // assert uses==0, delete
    //   前端 PTB: use_bpc → if 0 then destroy_empty_bpc

// === ProductionLine ===
entry fun create_production_line(name, recipe_id, ctx)
    // 建立 shared object: transfer::share_object(line)

entry fun authorize_operator(line: &mut ProductionLine, operator: address, ctx)
    // require_owner(line, ctx)
    // assert vec_set::size(&line.authorized_operators) < MAX_OPERATORS

entry fun revoke_operator(line: &mut ProductionLine, operator: address, ctx)
    // require_owner(line, ctx)

entry fun deposit_materials(line: &mut ProductionLine, recipe: &Recipe, item_type_id: u32, quantity: u64, ctx)
    // require_owner(line, ctx)
    // assert line.recipe_id == object::id(recipe)
    // assert item_type_id exists in recipe.inputs  (防止 Bag pollution)
    // Bag add or increment

entry fun deposit_fuel(line: &mut ProductionLine, amount: u64, ctx)
    // require_owner(line, ctx)

public fun start_production(line: &mut ProductionLine, recipe: &Recipe, blueprint: &BlueprintOriginal, clock: &Clock, ctx)
    // require_owner_or_operator(line, ctx)
    // assert line.recipe_id == object::id(recipe)
    // assert blueprint.recipe_id == object::id(recipe)
    // assert line.status == STATUS_IDLE
    // compute actual materials (ceiling division, u128)
    // assert input_buffer sufficient for each input
    // assert fuel_reserve >= energy_cost
    // deduct materials + fuel
    // compute actual_duration (ceiling division, u128)
    // set status=RUNNING, timestamps
    // emit ProductionStartedEvent { operator: sender }

public fun start_production_with_lease(line: &mut ProductionLine, recipe: &Recipe, lease: &LeaseAgreement, clock: &Clock, ctx)
    // require_owner_or_operator(line, ctx)
    // assert sender == lease.lessee  (只有承租方可使用)
    // 從 lease.bpo 讀取 ME/TE，同 start_production 邏輯
    // 不需要單獨的 borrow_leased_bpo → 直接在此函式中讀取 &lease.bpo

public fun complete_production(line: &mut ProductionLine, clock: &Clock, ctx)
    // require_owner_or_operator(line, ctx)  ← 修復：加 auth check
    // assert status == RUNNING && clock >= job_end
    // add output to output_buffer
    // set status=IDLE, increment jobs_completed
    // emit ProductionCompletedEvent { timestamp: clock_ms }

entry fun withdraw_output(line: &mut ProductionLine, item_type_id: u32, quantity: u64, ctx)
    // require_owner(line, ctx)  (operator 不可提取)
    // assert output_buffer has sufficient qty (防止 underflow)
    // deduct from output_buffer

// === TriggerEngine ===
entry fun create_trigger_rule(line: &ProductionLine, condition_type, threshold, target, cooldown, ctx) → TriggerRule
    // assert sender == line.owner  (驗證 line 所有權)
    // production_line_id = object::id(line)

entry fun toggle_trigger(rule: &mut TriggerRule, enabled: bool, ctx)

public fun evaluate_trigger(rule: &TriggerRule, line: &ProductionLine, clock: &Clock) → bool
    // 純讀取，不寫狀態
    // Bag missing key → quantity = 0 (用 bag::contains 檢查)
    // check enabled + cooldown + condition

public fun execute_trigger(rule: &mut TriggerRule, line: &mut ProductionLine, recipe: &Recipe, blueprint: &BlueprintOriginal, clock: &Clock, ctx)
    // require_owner_or_operator(line, ctx)
    // assert rule.production_line_id == object::id(line)
    // re-evaluate on-chain (TOCTOU 防護)
    // if valid: call start_production logic + update last_triggered
    // emit TriggerFiredEvent

// === Mock (demo only) ===
public fun mock_deposit_fuel(line: &mut ProductionLine, amount: u64, ctx)
    // require_owner(line, ctx)
    // 增加 fuel_reserve
    // ⚠ 部署前移除或加 #[test_only]
```

### 5.2 work_order

```
entry fun create_work_order(board: &mut WorkOrderBoard, item_type, qty, reward_coin: Coin<SUI>, deadline, priority, clock: &Clock, ctx)
    // assert coin::value(&reward_coin) >= MIN_ESCROW
    // assert deadline <= clock_ms + MAX_DEADLINE_MS
    // assert deadline > clock_ms  (不能過期)
    // escrow = coin::into_balance(reward_coin)
    // share_object(order)
    // table::add(&mut board.active_orders, order_id, true)
    // emit WorkOrderCreatedEvent

entry fun create_order_from_damage_report(board, report: DamageReport, reward_coin, clock, ctx)
    // auto priority=critical, 其餘同上

entry fun accept_work_order(order: &mut WorkOrder, ctx)
    // assert status == STATUS_OPEN
    // set acceptor = sender, status = ACCEPTED
    // emit WorkOrderAcceptedEvent

entry fun deliver_work_order(order: &mut WorkOrder, item_type_id: u32, quantity: u64, clock: &Clock, ctx)
    // assert sender == acceptor
    // assert item_type_id == order.item_type_id
    // assert quantity_delivered + quantity <= quantity_requested
    // increment quantity_delivered
    // if quantity_delivered >= quantity_requested:
    //   set delivered_at = Some(clock_ms), status = DELIVERED

public fun complete_work_order(order: &mut WorkOrder, board: &mut WorkOrderBoard, ctx) → Coin<SUI>
    // assert sender == issuer
    // assert status == DELIVERED
    // release escrow to acceptor
    // table::remove(&mut board.active_orders, order_id)
    // emit WorkOrderCompletedEvent

public fun auto_complete_work_order(order: &mut WorkOrder, board: &mut WorkOrderBoard, clock: &Clock, ctx) → Coin<SUI>
    // assert sender == acceptor
    // assert status == DELIVERED
    // assert order.delivered_at.is_some()
    // assert clock >= delivered_at.unwrap() + AUTO_COMPLETE_GRACE_MS
    // release escrow to acceptor

entry fun cancel_work_order(order: &mut WorkOrder, board: &mut WorkOrderBoard, ctx) → Coin<SUI>
    // assert sender == issuer && status == STATUS_OPEN
    // full refund, remove from board
    // emit WorkOrderCancelledEvent

entry fun cancel_expired_order(order: &mut WorkOrder, board: &mut WorkOrderBoard, clock: &Clock, ctx) → Coin<SUI>
    // assert clock > deadline
    // if accepted but not delivered: 90% → issuer, 10% → acceptor
    // if not accepted: full refund → issuer
    // emit WorkOrderCancelledEvent
```

### 5.3 marketplace

```
// Admin
entry fun update_fee(market: &mut Marketplace, _cap: &MarketplaceAdminCap, new_bps: u64)

// BPO 買賣
entry fun list_bpo(market: &mut Marketplace, bpo: BlueprintOriginal, price: u64, clock: &Clock, ctx)
    // assert price >= MIN_LISTING_PRICE
    // wrap BPO into BpoListing, transfer listing to sender (or share)
    // emit BpoListedEvent

public fun buy_bpo(market: &mut Marketplace, listing: BpoListing, payment: &mut Coin<SUI>, ctx) → BlueprintOriginal
    // assert coin::value(payment) >= price
    // fee = max(1, price * fee_bps / 10000)  ← 最低 1 MIST 手續費
    // take exactly `price` from payment (剩餘留在 payment coin，PTB 中退回 buyer)
    // seller gets price - fee, fee_collector += fee
    // unwrap BPO, return to caller
    // emit BlueprintPurchasedEvent

entry fun delist_bpo(listing: BpoListing, ctx) → BlueprintOriginal
    // assert sender == seller

// BPC 買賣 (同 BPO pattern)
entry fun list_bpc(...)
public fun buy_bpc(...)
entry fun delist_bpc(...)

// BPO 租賃
entry fun create_lease(bpo: BlueprintOriginal, lessee: address, fee: u64, duration: u64, deposit_coin: Coin<SUI>, clock: &Clock, ctx)
    // wrap BPO into LeaseAgreement
    // transfer lease_fee to lessor
    // deposit 託管
    // share_object(lease)  ← Shared Object
    // emit LeaseCreatedEvent

entry fun return_lease(lease: LeaseAgreement, ctx)
    // assert sender == lessee  ← 修復：加 sender check
    // destroy LeaseAgreement
    // transfer BPO to lessor
    // refund deposit to lessee
    // emit LeaseReturnedEvent

entry fun forfeit_lease(lease: LeaseAgreement, clock: &Clock, ctx)
    // assert sender == lessor  ← 修復：加 sender check
    // assert clock > start_time + duration_ms
    // destroy LeaseAgreement
    // transfer BPO to lessor
    // deposit goes to lessor
    // emit LeaseReturnedEvent

// mock_deposit_fuel 已移到 industrial_core
```

---

## 6. Off-chain Architecture

### 6.1 Event Watcher Service (TypeScript + @mysten/sui)

```
┌─────────────────────────────────────────────┐
│            Event Watcher Service              │
│                                               │
│  FleetCMDListener ─── WebSocket subscribe     │
│    監聽 BattleDamageEvent                      │
│                                               │
│  InventoryMonitor ─── Polling (10s)           │
│    查詢 ProductionLine buffer 數量             │
│                                               │
│  DeadlineScheduler ── Polling (60s)           │
│    檢查 WorkOrder 過期                         │
│                                               │
│         ┌─────────────┐                       │
│         │ Rule Matcher │                       │
│         │ 比對 TriggerRule                     │
│         │ 呼叫鏈上 evaluate_trigger()          │
│         └──────┬──────┘                       │
│                ▼                               │
│         ┌─────────────┐                       │
│         │ TX Executor  │                       │
│         │ 簽名送鏈上 tx │                       │
│         └─────────────┘                       │
└─────────────────────────────────────────────┘
```

### 6.2 Watcher Identity & Authorization

- Watcher 持有專屬 service keypair
- 玩家呼叫 `authorize_operator(watcher_address)`
- 合約 `execute_trigger()` 檢查 `require_owner_or_operator()`
- Gas: devnet faucet (Hackathon), 未來 Sponsored Transaction

### 6.3 Error Recovery

| 故障模式 | 處理策略 |
|---|---|
| WebSocket 斷線 | 指數退避重連 (1s→2s→4s→max 30s)，從 last_cursor 續讀 |
| Tx gas 不足 | alert log + 跳過，不 retry 同一觸發 |
| evaluate_trigger false | 靜默跳過 |
| 輪詢 timeout | 下一 interval 重試，連續 3 次 → alert |
| 重複觸發 | in-memory cooldown map + 鏈上 cooldown_ms 雙重防護 |

---

## 7. Frontend Architecture

### 7.1 Tech Stack

```
React + TypeScript
├── @mysten/dapp-kit-react  — 錢包連接、tx 簽名（取代已棄用的 @mysten/dapp-kit）
├── @mysten/sui             — PTB 構建、RPC / GraphQL 查詢
├── @tanstack/react-query   — 資料快取 + refetch
├── Tailwind CSS            — 樣式
└── Recharts                — 生產數據視覺化

Setup:
- createDAppKit() + DAppKitProvider（取代舊的三層 Provider）
- SuiGrpcClient (非 JSON-RPC)
- declare module '@mysten/dapp-kit-react' 型別擴展
```

### 7.2 Page Structure (5 頁)

```
/                       Dashboard — 工廠總覽 + 產線狀態燈號 + 戰損 feed + 觸發事件 log
/factory/:id            產線詳情 — 進度條(client-side timer)、buffer、配方、觸發規則、operator 管理
/orders                 工單中心 — 公開看板 + 我的工單(tab) + 發單/接單/交付
/blueprints             藍圖中心 — 我的 BPO/BPC + Listing/Lease 中的(wrapped) + 市場(tab)
/monitor                即時監控 — 全事件 stream (suiClient.subscribeEvent)
```

### 7.3 Data Flow Pattern

```
鏈上資料 → react-query (refetchInterval 5s + event-driven invalidation)
UI 狀態  → React useState/useReducer
即時事件 → suiClient.subscribeEvent() 直接在 browser 訂閱
寫入操作 → signAndExecuteTransaction → waitForTransaction → invalidateQueries
          (必須 waitForTransaction 後再 invalidate，否則 indexer 未跟上)

所有 wallet-dependent query 加 enabled: !!account guard
```

### 7.4 關鍵 PTB 組合

```
Flow A: 存料 + 加油 + 開工（單一 PTB）
  moveCall: deposit_materials(line, recipe, item_type_id, qty)
  moveCall: deposit_fuel(line, amount)
  moveCall: start_production(line, recipe, blueprint, clock)

Flow B: 買 BPC（含找零）
  splitCoins(gas, [price]) → payment
  moveCall: buy_bpc(market, listing, &mut payment) → bpc
  transferObjects(payment, sender)  // 找零退回

Flow C: 建工單（escrow）
  splitCoins(gas, [reward]) → coin
  moveCall: create_work_order(board, item_type, qty, coin, deadline, priority, clock)

Flow D: 承租方生產
  moveCall: start_production_with_lease(line, recipe, lease, clock)
  // 不需要 borrow_leased_bpo — 函式內部直接讀取 lease.bpo
```

### 7.5 Wrapped Object 查詢

```
/blueprints 頁面需要顯示三種狀態的 BPO：
1. 持有中 → getOwnedObjects({ type: BlueprintOriginal })
2. 上架中 → queryEvents(BpoListedEvent) 或 getOwnedObjects({ type: BpoListing })
3. 出租中 → queryEvents(LeaseCreatedEvent) 或 getDynamicFields

Demo 建議：pre-seed devnet 配方和 BPO，避免需要 create_recipe UI
```

---

## 8. Cross-Project Integration

### 8.1 Fleet Command (真實整合)

```
Fleet Command 合約
    │ emit BattleDamageEvent
    ▼
Watcher: FleetCMDListener
    │ extract DamageReport
    ▼
work_order::create_order_from_damage_report()
    │ WorkOrder(priority=critical) created
    ▼
TriggerRule(condition_type=external_event) matched
    │
    ▼
industrial_core::execute_trigger()
    │ ProductionLine auto-starts
    ▼
成品 → deliver_work_order() → escrow 結算
```

### 8.2 AstroLogistics (Mock)

- `mock_deposit_fuel()` in industrial_core: 模擬燃料存入
- 前端顯示燃料消耗數字
- 介面預留 `consume_fuel(hub: &mut Hub, amount: u64)` 簽名

### 8.3 Wreckage Insurance (Mock)

- 模擬殘骸回收產出的再生原料
- 介面預留 `receive_salvage()` entry function

---

## 9. Error Handling

### 9.1 Error Code Convention (所有 error 加 #[error] annotation)

```move
// industrial_core: 0-99
#[error] const E_NOT_OWNER: u64 = 0;
#[error] const E_NOT_AUTHORIZED_OPERATOR: u64 = 1;
#[error] const E_INSUFFICIENT_MATERIALS: u64 = 2;
#[error] const E_PRODUCTION_LINE_BUSY: u64 = 3;
#[error] const E_PRODUCTION_NOT_COMPLETE: u64 = 4;
#[error] const E_BLUEPRINT_NO_USES_LEFT: u64 = 5;
#[error] const E_BLUEPRINT_MAX_COPIES_REACHED: u64 = 6;
#[error] const E_TRIGGER_DISABLED: u64 = 7;
#[error] const E_TRIGGER_CONDITION_NOT_MET: u64 = 8;
#[error] const E_TRIGGER_COOLDOWN: u64 = 9;
#[error] const E_INVALID_RECIPE: u64 = 10;
#[error] const E_RECIPE_BLUEPRINT_MISMATCH: u64 = 11;
#[error] const E_INSUFFICIENT_FUEL: u64 = 12;
#[error] const E_EFFICIENCY_OUT_OF_RANGE: u64 = 13;
#[error] const E_ZERO_MATERIAL_AFTER_EFFICIENCY: u64 = 14;
#[error] const E_RECIPE_EMPTY_INPUTS: u64 = 15;
#[error] const E_RECIPE_ZERO_QUANTITY: u64 = 16;
#[error] const E_MAX_OPERATORS_REACHED: u64 = 17;
#[error] const E_INVALID_ITEM_TYPE: u64 = 18;  // deposit 的 item 不在 recipe inputs 中
#[error] const E_TRIGGER_LINE_MISMATCH: u64 = 19;

// work_order: 100-199
#[error] const E_ORDER_NOT_OPEN: u64 = 100;
#[error] const E_ORDER_ALREADY_ACCEPTED: u64 = 101;
#[error] const E_DELIVERY_TYPE_MISMATCH: u64 = 102;
#[error] const E_DELIVERY_QUANTITY_EXCEEDS: u64 = 103;
#[error] const E_ORDER_EXPIRED: u64 = 104;
#[error] const E_INSUFFICIENT_ESCROW: u64 = 105;
#[error] const E_NOT_ISSUER: u64 = 106;
#[error] const E_NOT_ACCEPTOR: u64 = 107;
#[error] const E_AUTO_COMPLETE_TOO_EARLY: u64 = 108;
#[error] const E_DEADLINE_TOO_FAR: u64 = 109;
#[error] const E_DEADLINE_IN_PAST: u64 = 110;

// marketplace: 200-299
#[error] const E_LISTING_PRICE_TOO_LOW: u64 = 200;
#[error] const E_PAYMENT_INSUFFICIENT: u64 = 201;
#[error] const E_LEASE_NOT_EXPIRED: u64 = 202;
#[error] const E_NOT_SELLER: u64 = 203;
#[error] const E_NOT_LESSEE: u64 = 204;
#[error] const E_NOT_LESSOR: u64 = 205;
```

### 9.2 Key Defensive Patterns

1. **時間驗證**：`complete_production` 用 `Clock` 驗證生產時間已到
2. **BPC 使用+銷毀**：`use_bpc` decrement → `destroy_empty_bpc` 歸零時銷毀（PTB 中組合）
3. **Escrow 不卡死**：deadline 過後可觸發 cancel + auto_complete 72h 機制
4. **Operator 權限隔離**：嚴格按權限矩陣，operator 只能 start/complete，不能 withdraw/deposit
5. **BPO 鑄造安全**：mint_bpc 需要 `&mut BPO`，wrap 狀態下外部無法取得
6. **效率計算安全**：ceiling division + u128 中間運算 + assert >= 1
7. **Recipe 驗證**：non-empty inputs, all quantities > 0, energy_cost > 0
8. **Bag 安全**：deposit 驗證 item_type_id 在 recipe inputs 中；evaluate 用 contains 檢查 missing key
9. **Fee 最低保障**：`max(1, computed_fee)` 防止微交易零手續費
10. **Deadline 上限**：WorkOrder deadline <= 30 天，防止永久鎖定 escrow

---

## 10. Testing Strategy

### 10.1 Unit Tests (Move #[test])

| Module | Tests |
|---|---|
| recipe | create valid, empty inputs fails, zero quantity fails, zero duration fails, zero energy fails |
| blueprint | mint BPO, ME/TE > 25 fails, mint BPC increments copies_minted, max copies fails, use BPC decrements, destroy empty BPC, destroy non-empty fails |
| production_line | create shared, auth: owner ok / operator rejected for withdraw / non-auth rejected, deposit validates item_type_id against recipe, insufficient materials, complete before time fails, correct output, ceiling division edge cases (qty=1 ME=25) |
| trigger_engine | create requires line owner, below threshold true, above threshold false, missing Bag key = 0 (not abort), disabled fails, cooldown prevents double, line_id mismatch fails |
| work_order | escrow on create, min escrow fails, max deadline fails, accept already accepted fails, wrong type delivery fails, complete releases, auto_complete before 72h fails, cancel expired 90/10 split, cancel not-accepted full refund |
| marketplace | min price check, list+buy fee split (max(1,fee)), buy overpayment returns change, delist returns, lease sender checks (return=lessee, forfeit=lessor), forfeit before expiry fails |

### 10.2 Integration Tests

- `test_full_production_cycle`: Recipe → BPO → Line → Deposit(validated) → Produce → Withdraw
- `test_damage_report_to_auto_production`: DamageReport → WorkOrder → Trigger → Auto-produce
- `test_work_order_full_lifecycle`: Create(escrow) → Accept → Deliver → Complete → Settle
- `test_blueprint_market_to_production`: List BPC → Buy → Use in line → destroy at 0
- `test_lease_production_flow`: Create lease → start_production_with_lease → return_lease

### 10.3 Monkey Tests (Adversarial)

| Test | 攻擊向量 | 預期結果 |
|---|---|---|
| `test_operator_withdraw_attempt` | operator 呼叫 withdraw_output | abort E_NOT_OWNER |
| `test_efficiency_qty_1_me_25` | 1 * 75 / 100 rounding | ceiling → 1, 不是 0 |
| `test_deposit_invalid_item_type` | deposit 不在 recipe inputs 的 item | abort E_INVALID_ITEM_TYPE |
| `test_bag_missing_key_evaluate` | 從未 deposit 過的 item 做 trigger 評估 | returns true (qty=0 < threshold) |
| `test_concurrent_trigger` | 兩個 tx 同時 execute_trigger | 第二個 fail (Sui sequential for shared obj) |
| `test_lease_lessee_mint_bpc` | 承租方嘗試 mint_bpc | 無法取得 &mut BPO → abort |
| `test_lease_orphan_recovery` | lessee 消失，lessor forfeit | 成功取回 BPO + deposit |
| `test_order_infinite_deadline` | deadline = u64::MAX | abort E_DEADLINE_TOO_FAR |
| `test_micro_price_fee_evasion` | price = MIN_LISTING_PRICE - 1 | abort E_LISTING_PRICE_TOO_LOW |
| `test_buy_overpayment` | 付 10 SUI 買 5 SUI 的 listing | 找零 5 SUI 退回 |
| `test_return_lease_by_stranger` | 第三方呼叫 return_lease | abort E_NOT_LESSEE |
| `test_forfeit_before_expiry` | lessor 提前 forfeit | abort E_LEASE_NOT_EXPIRED |
| `test_empty_recipe_free_production` | inputs=[] | abort E_RECIPE_EMPTY_INPUTS |
| `test_u64_overflow_deposit` | deposit u64::MAX when buffer has 1 | Move abort (overflow) |
| `test_auto_complete_before_72h` | acceptor 立即 auto_complete | abort E_AUTO_COMPLETE_TOO_EARLY |

---

## 11. Real-World Analogy

| 遊戲概念 | 現實對照 |
|---|---|
| Recipe | 工廠 SOP / BOM 表 |
| BPO | 高通 5G 專利（永久持有） |
| BPC | 專利授權書（限量限次數） |
| BPO 租賃 | ARM IP 授權模式 |
| ProductionLine | 富士康產線（效率參數因師傅而異） |
| TriggerRule | 豐田 JIT 自動補貨系統 |
| WorkOrder + Escrow | 五角大樓軍工採購合約（預算撥款） |
| DamageReport → 自動補產 | 前線戰損報告 → 後方兵工廠加班 |
| Marketplace | 技術授權交易市場 |

---

## 12. Audit Summary

### Reviews Completed

| Agent | Focus | Critical | High | Medium |
|---|---|---|---|---|
| sui-architect | 架構/Object model/升級 | 2 | 0 | 2 |
| sui-security-guard | 存取控制/經濟攻擊/DoS | 2 | 5 | 6 |
| sui-red-team | 對抗性攻擊模擬 | 5 | 12 | 7 |
| sui-developer | Move 2024 慣例/型別/PTB | 2 | 0 | 4 |
| sui-frontend | dApp Kit/資料流/頁面 | 1 | 0 | 3 |

### All Critical Issues (Resolved in This Revision)

| ID | Issue | Fix |
|---|---|---|
| ARCH-1 | ProductionLine 必須是 shared object | ✅ 改為 shared + 權限矩陣 |
| ARCH-2 | borrow_leased_bpo API 不可行 | ✅ 改為 start_production_with_lease |
| SEC-1 | 效率計算 u64 溢位 | ✅ u128 中間運算 + ceiling division |
| SEC-2 | delivered_at 欄位缺失 | ✅ 新增欄位 + auto_complete 邏輯 |
| RED-1 | 效率小數量歸零 (1*75/100=0) | ✅ ceiling division + assert >= 1 |
| RED-2 | 空 recipe inputs 免費生產 | ✅ create_recipe 驗證 non-empty |
| RED-3 | BPC zombie (未銷毀) | ✅ use + destroy 分離但 PTB 組合 |
| RED-4 | LeaseAgreement owned → BPO 鎖死 | ✅ 改為 shared object |
| RED-5 | Bag key pollution | ✅ deposit 驗證 item_type_id |
| DEV-1 | WorkOrder/LeaseAgreement 不能有 store | ✅ 移除 store，改為 shared |
| DEV-2 | 缺 BPC 版 start_production | ✅ BPC 效率在 use_bpc 取得後傳入 |
| FE-1 | @mysten/dapp-kit 已棄用 | ✅ 改為 @mysten/dapp-kit-react |

### Red Team Report

完整報告：`docs/superpowers/specs/2026-03-20-red-team-report.md`


### 2026 03 20 Red Team Report

# Red Team Report: Industrial Auto OS

> Adversarial security analysis of system spec
> Date: 2026-03-20
> Status: Pre-implementation (spec-level)
> Analyst: sui-red-team

---

## 1. ACCESS CONTROL BYPASS

### 1.1 [CRITICAL] Operator Escalation: Withdraw via Authorized Operator

**Scenario**: `start_production` checks `is_owner || is_authorized_operator`. If implementation copies same auth pattern to `withdraw_output`, an authorized watcher drains the output buffer.

**Impact**: Operator steals all produced goods.

**Countermeasure**: Strict function-level permission matrix. `withdraw_output`, `deposit_materials`, `authorize_operator`, `revoke_operator` = owner-only. Split into `require_owner()` and `require_owner_or_operator()`.

### 1.2 [HIGH] Lease BPO Read-Reference Abuse

**Scenario**: `borrow_leased_bpo()` returns `&BlueprintOriginal`. If `mint_bpc` mistakenly accepts `&BlueprintOriginal` instead of `&mut BlueprintOriginal`, lessee can mint BPCs from leased BPO.

**Impact**: Unlimited BPC minting from unowned BPO.

**Countermeasure**: `mint_bpc` MUST take `bpo: &mut BlueprintOriginal`. Add test: lessee calls mint_bpc with leased BPO -> must abort.

### 1.3 [HIGH] ProductionLine Shared Object Auth Gap

**Scenario**: If `ProductionLine` is shared, anyone can pass `&mut ProductionLine` to any function. Every mutating function must check owner/operator.

**Impact**: Any player can manipulate another's production line.

**Countermeasure**: Either keep as owned object (safer) or assert `sender == owner || is_authorized_operator(sender)` in EVERY mutating function. No exceptions.

### 1.4 [MEDIUM] TriggerRule Creator != ProductionLine Owner

**Scenario**: `create_trigger_rule` takes `line_id: ID` (just an ID). Anyone can create rules pointing to someone else's line. `execute_trigger` must verify `rule.production_line_id == object::id(line)`.

**Impact**: Unauthorized trigger execution.

**Countermeasure**: `create_trigger_rule` should take `&ProductionLine` and verify sender is owner. `execute_trigger` must assert `rule.production_line_id == object::id(line)`.

---

## 2. INTEGER/ARITHMETIC ABUSE

### 2.1 [CRITICAL] Material Efficiency Rounding to Zero

**Scenario**: `actual = base_quantity * (100 - ME) / 100`. If `base_quantity = 1` and `ME = 25`, then `actual = 75 / 100 = 0`. Free production.

**Impact**: Infinite free production.

**Countermeasure**:
```move
let actual = (base_quantity * (100 - (me as u64)) + 99) / 100; // ceiling division
assert!(actual >= 1, E_ZERO_MATERIAL_AFTER_EFFICIENCY);
```

### 2.2 [HIGH] u64 Overflow in Quantity Accumulation

**Scenario**: Deposit `u64::MAX - current + 1` overflows the Bag counter.

**Impact**: Material counter wraps to near-zero.

**Countermeasure**: Move aborts on overflow by default. Never use wrapping arithmetic. Add test: deposit u64::MAX when buffer has 1 -> must abort.

### 2.3 [HIGH] Fee Calculation Rounding Exploit

**Scenario**: `fee = price * fee_bps / 10000`. If `price = 3`, `fee_bps = 250`, fee = 0.

**Impact**: Zero-fee trades on micro-transactions.

**Countermeasure**: `fee = max(1, price * fee_bps / 10000)`. Or enforce minimum listing price.

### 2.4 [MEDIUM] copies_minted Unbounded Growth (max_copies=0)

**Scenario**: Unlimited minting with max_copies=0. copies_minted grows forever.

**Impact**: Low practical risk (u64::MAX unreachable).

**Countermeasure**: Document behavior. No code change needed.

---

## 3. OBJECT MANIPULATION

### 3.1 [CRITICAL] BPC Zombie: uses_remaining=0 Never Destroyed

**Scenario**: `use_bpc` decrements uses but caller must separately call `destroy_bpc`. If caller doesn't, zombie BPC persists.

**Impact**: Object pollution, potential logic bugs if code checks existence.

**Countermeasure**: Single function: `use_bpc(bpc: BlueprintCopy) -> Option<BlueprintCopy>`. Returns `None` (destroyed) at 0 uses, `Some(bpc)` otherwise.

### 3.2 [HIGH] Orphaned LeaseAgreement

**Scenario**: If LeaseAgreement is owned by lessee and lessee disappears, lessor cannot access it to call `forfeit_lease`. BPO permanently locked.

**Impact**: Permanent BPO loss.

**Countermeasure**: `LeaseAgreement` MUST be shared object. Both lessor and lessee can call their respective functions.

### 3.3 [HIGH] WorkOrder Stuck with Infinite Deadline

**Scenario**: Deadline set to u64::MAX. Acceptor disappears. Escrow locked forever (cancel_expired_order can never trigger).

**Impact**: Permanent escrow lock.

**Countermeasure**: `assert!(deadline <= clock::timestamp_ms(clock) + MAX_DEADLINE_MS)` where MAX_DEADLINE_MS = 30 days.

### 3.4 [MEDIUM] WorkOrderBoard vector<ID> Unbounded Growth

**Scenario**: open_orders vector grows without bound as orders accumulate.

**Impact**: Gas costs spike, board becomes unusable.

**Countermeasure**: Use `LinkedTable<ID, bool>` or `Table<ID, bool>` instead of `vector<ID>`.

---

## 4. ECONOMIC EXPLOITS

### 4.1 [CRITICAL] Free Production via Empty Recipe Inputs

**Scenario**: `create_recipe` with `inputs: []` and non-zero output. Infinite item minting from nothing.

**Impact**: Complete economic collapse.

**Countermeasure**:
```move
assert!(vector::length(&inputs) > 0, E_RECIPE_NO_INPUTS);
assert!(output.quantity > 0, E_RECIPE_ZERO_OUTPUT);
```
Consider admin-gated recipe creation.

### 4.2 [HIGH] Marketplace Fee Evasion via Direct Transfer

**Scenario**: Players use `transfer::public_transfer` to trade BPO/BPC directly, bypassing marketplace fees.

**Impact**: Zero fee collection.

**Countermeasure**: Accept as inherent (marketplace = convenience) or remove `store` ability / use Kiosk + Transfer Policy.

### 4.3 [HIGH] auto_complete Delivery Gaming

**Scenario**: Acceptor delivers matching item_type_id and quantity but no actual items transferred on-chain. Waits 72h, auto-completes, gets paid.

**Impact**: Payment without real delivery.

**Countermeasure**: Delivery must involve actual on-chain material transfer (not just counter increment). Or add dispute mechanism.

### 4.4 [MEDIUM] Dust Attack on WorkOrder

**Scenario**: Thousands of 1-MIST escrow orders pollute the board.

**Impact**: Board bloat, legitimate orders hidden.

**Countermeasure**: Enforce minimum escrow: `assert!(coin::value(&reward_coin) >= MIN_ORDER_REWARD)`.

---

## 5. ORDERING/TIMING ATTACKS

### 5.1 [HIGH] Front-Running Trigger Execution

**Scenario**: Adversary operator sees watcher's trigger tx in mempool, front-runs to execute at suboptimal time.

**Impact**: Sabotaged production timing.

**Countermeasure**: Limit to one operator per line, or accept as inherent multi-operator risk.

### 5.2 [HIGH] Tight Deadline Griefing

**Scenario**: Create order with tight deadline, wait for acceptance. After deadline: 90% refund to issuer, acceptor wasted effort for 10%.

**Impact**: Griefing acceptors.

**Countermeasure**: Compensation scales with delivery progress. Enforce minimum deadline (1 hour).

### 5.3 [MEDIUM] auto_complete 72h Clock Ambiguity

**Scenario**: No `last_delivery_timestamp` field. 72h clock start is undefined. Acceptor can game the timing.

**Impact**: Bypasses 72h grace period.

**Countermeasure**: Add `last_full_delivery_timestamp: u64`. Clock starts when `quantity_delivered >= quantity_requested`.

### 5.4 [MEDIUM] Cascading Trigger After Production Complete

**Scenario**: Precisely timed `complete_production` immediately triggers another auto-start via TriggerRule.

**Impact**: Uncontrolled production cascading.

**Countermeasure**: Minimum idle time between productions or per-trigger cooldown (already in spec).

---

## 6. DOS VECTORS

### 6.1 [CRITICAL] Bag Key Pollution in Buffers

**Scenario**: Attacker deposits 1 unit of thousands of different item_type_ids. Bag grows unboundedly.

**Impact**: Production gas costs spike, line unusable.

**Countermeasure**: Auth on deposit (owner-only). Validate item_type_id against recipe inputs. Limit max unique item types.

### 6.2 [HIGH] authorized_operators Vector Unbounded

**Scenario**: No size limit or dedup on operator list. Linear scan on every auth check.

**Impact**: Auth check gas grows linearly.

**Countermeasure**: Use `VecSet<address>`. Max 10 operators.

### 6.3 [HIGH] WorkOrder Spam on Shared Board

**Scenario**: Thousands of minimal orders flood open_orders vector.

**Impact**: Board becomes gas bomb.

**Countermeasure**: `Table` instead of `vector`. Minimum escrow. Rate-limit per address.

### 6.4 [MEDIUM] TriggerRule Spam

**Scenario**: Anyone creates thousands of rules pointing to one line. Watcher must evaluate all.

**Impact**: Watcher resource exhaustion.

**Countermeasure**: `create_trigger_rule` requires `&ProductionLine` + owner check. Store rules inside ProductionLine with max cap (10).

---

## Summary

| Category | Critical | High | Medium | Total |
|----------|----------|------|--------|-------|
| Access Control | 1 | 2 | 1 | 4 |
| Integer/Arithmetic | 1 | 2 | 1 | 4 |
| Object Manipulation | 1 | 2 | 1 | 4 |
| Economic Exploits | 1 | 2 | 1 | 4 |
| Ordering/Timing | 0 | 2 | 2 | 4 |
| DoS Vectors | 1 | 2 | 1 | 4 |
| **Total** | **5** | **12** | **7** | **24** |

## Top 5 Must-Fix Before Implementation

1. **Material efficiency rounding to zero** (2.1) -- ceiling division or minimum 1
2. **Free production via empty recipe** (4.1) -- assert inputs non-empty
3. **BPC zombie objects** (3.1) -- use-and-destroy in single function
4. **LeaseAgreement must be shared** (3.2) -- or BPO permanently lost
5. **Bag pollution in buffers** (6.1) -- auth on deposit + validate against recipe

## Implementation Checklist

- [ ] Every mutating function on ProductionLine checks auth
- [ ] Material efficiency uses ceiling division, asserts >= 1
- [ ] BPC use_and_destroy is a single atomic function
- [ ] LeaseAgreement is shared object
- [ ] Recipe creation requires non-empty inputs
- [ ] WorkOrder deadline has maximum cap
- [ ] Marketplace enforces minimum listing price
- [ ] WorkOrderBoard uses Table, not vector
- [ ] authorized_operators uses VecSet with max cap
- [ ] deposit_materials validates item_type_id against recipe
- [ ] TriggerRule creation requires ProductionLine reference + owner check
- [ ] Fee calculation uses max(1, computed_fee)
- [ ] Minimum escrow for WorkOrder creation
- [ ] auto_complete tracks last_full_delivery_timestamp


### 2026 03 21 Offchain Watcher Design

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


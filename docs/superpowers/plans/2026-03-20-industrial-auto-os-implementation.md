# Industrial Auto OS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full-function on-chain industrial automation system for EVE Frontier with 3 Move packages, off-chain watcher, and React frontend.

**Architecture:** Core + Satellite pattern. `industrial_core` (recipes, blueprints, production lines, triggers) is the foundation; `work_order` and `marketplace` are satellite packages that depend on it. Off-chain watcher bridges Fleet Command events to on-chain triggers. React frontend uses @mysten/dapp-kit-react.

**Tech Stack:** Sui Move 1.68, TypeScript, @mysten/sui, @mysten/dapp-kit-react, React, Tailwind CSS, Recharts

**Spec:** `docs/superpowers/specs/2026-03-20-industrial-auto-os-design.md`
**Red Team Report:** `docs/superpowers/specs/2026-03-20-red-team-report.md`

---

## File Structure

```
packages/
├── industrial_core/
│   ├── Move.toml
│   ├── sources/
│   │   ├── recipe.move
│   │   ├── blueprint.move
│   │   ├── production_line.move
│   │   ├── trigger_engine.move
│   │   └── mock_fuel.move
│   └── tests/
│       ├── recipe_tests.move
│       ├── blueprint_tests.move
│       ├── production_line_tests.move
│       ├── trigger_engine_tests.move
│       └── integration_tests.move
│
├── work_order/
│   ├── Move.toml
│   ├── sources/
│   │   ├── work_order.move
│   │   └── fleet_integration.move
│   └── tests/
│       ├── work_order_tests.move
│       └── fleet_integration_tests.move
│
├── marketplace/
│   ├── Move.toml
│   ├── sources/
│   │   ├── marketplace.move
│   │   └── lease.move
│   └── tests/
│       ├── marketplace_tests.move
│       └── lease_tests.move
│
watcher/
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts
│   ├── config.ts
│   ├── listeners/
│   │   ├── fleet-cmd-listener.ts
│   │   ├── inventory-monitor.ts
│   │   └── deadline-scheduler.ts
│   ├── rule-matcher.ts
│   └── tx-executor.ts
│
frontend/
├── package.json
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.ts
├── src/
│   ├── main.tsx
│   ├── App.tsx
│   ├── sui-config.ts
│   ├── constants.ts                  (package IDs, type names)
│   ├── hooks/
│   │   ├── useProductionLines.ts
│   │   ├── useWorkOrders.ts
│   │   ├── useBlueprints.ts
│   │   └── useEvents.ts
│   ├── pages/
│   │   ├── Dashboard.tsx
│   │   ├── FactoryDetail.tsx
│   │   ├── Orders.tsx
│   │   ├── Blueprints.tsx
│   │   └── Monitor.tsx
│   ├── components/
│   │   ├── ProductionLineCard.tsx
│   │   ├── WorkOrderCard.tsx
│   │   ├── BlueprintCard.tsx
│   │   ├── EventFeed.tsx
│   │   └── CountdownTimer.tsx
│   └── lib/
│       └── ptb-builders.ts           (PTB construction helpers)
```

---

## Phase 1: industrial_core Package

### Task 1: Project Scaffold + Recipe Module

**Files:**
- Create: `packages/industrial_core/Move.toml`
- Create: `packages/industrial_core/sources/recipe.move`
- Create: `packages/industrial_core/tests/recipe_tests.move`

- [ ] **Step 1: Create Move.toml**

```toml
[package]
name = "industrial_core"
edition = "2024.beta"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }

[addresses]
industrial_core = "0x0"
```

- [ ] **Step 2: Write recipe test scaffolding**

```move
// tests/recipe_tests.move
#[test_only]
module industrial_core::recipe_tests;

use industrial_core::recipe;

#[test]
fun test_create_recipe_valid() {
    let mut ctx = tx_context::dummy();
    let inputs = vector[recipe::new_material_req(101, 500)];
    let output = recipe::new_material_output(201, 1);
    let r = recipe::create_recipe(
        b"Frigate Hull".to_string(),
        inputs,
        output,
        60_000, // 60s
        100,    // energy
        &mut ctx,
    );
    assert!(recipe::name(&r) == b"Frigate Hull".to_string());
    assert!(recipe::energy_cost(&r) == 100);
    assert!(recipe::base_duration_ms(&r) == 60_000);
    assert!(vector::length(recipe::inputs(&r)) == 1);
    sui::test_utils::destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_RECIPE_EMPTY_INPUTS)]
fun test_create_recipe_empty_inputs_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[],
        recipe::new_material_output(201, 1),
        60_000,
        100,
        &mut ctx,
    );
    sui::test_utils::destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_RECIPE_ZERO_QUANTITY)]
fun test_create_recipe_zero_input_quantity_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[recipe::new_material_req(101, 0)],
        recipe::new_material_output(201, 1),
        60_000,
        100,
        &mut ctx,
    );
    sui::test_utils::destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_RECIPE_ZERO_QUANTITY)]
fun test_create_recipe_zero_output_quantity_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[recipe::new_material_req(101, 500)],
        recipe::new_material_output(201, 0),
        60_000,
        100,
        &mut ctx,
    );
    sui::test_utils::destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_INVALID_RECIPE)]
fun test_create_recipe_zero_duration_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[recipe::new_material_req(101, 500)],
        recipe::new_material_output(201, 1),
        0,
        100,
        &mut ctx,
    );
    sui::test_utils::destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_INVALID_RECIPE)]
fun test_create_recipe_zero_energy_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[recipe::new_material_req(101, 500)],
        recipe::new_material_output(201, 1),
        60_000,
        0,
        &mut ctx,
    );
    sui::test_utils::destroy(r);
}
```

- [ ] **Step 3: Run tests — expect compile error (module not found)**

Run: `cd packages/industrial_core && sui move test`
Expected: FAIL — `recipe` module doesn't exist yet

- [ ] **Step 4: Implement recipe.move**

```move
// sources/recipe.move
module industrial_core::recipe;

use std::string::String;

// === Error Codes ===
#[error]
const E_RECIPE_EMPTY_INPUTS: u64 = 15;
#[error]
const E_RECIPE_ZERO_QUANTITY: u64 = 16;
#[error]
const E_INVALID_RECIPE: u64 = 10;

// === Structs ===
public struct MaterialRequirement has store, copy, drop {
    item_type_id: u32,
    quantity: u64,
}

public struct MaterialOutput has store, copy, drop {
    item_type_id: u32,
    quantity: u64,
}

public struct Recipe has key, store {
    id: UID,
    name: String,
    inputs: vector<MaterialRequirement>,
    output: MaterialOutput,
    base_duration_ms: u64,
    energy_cost: u64,
    creator: address,
}

// === Constructors ===
public fun new_material_req(item_type_id: u32, quantity: u64): MaterialRequirement {
    MaterialRequirement { item_type_id, quantity }
}

public fun new_material_output(item_type_id: u32, quantity: u64): MaterialOutput {
    MaterialOutput { item_type_id, quantity }
}

/// public fun (非 entry) — 回傳 Recipe 供 caller 決定 transfer 或 wrap。
/// 測試中用 sui::test_utils::destroy()，正式使用時在 PTB 中 transfer::public_transfer(recipe, sender)。
public fun create_recipe(
    name: String,
    inputs: vector<MaterialRequirement>,
    output: MaterialOutput,
    base_duration_ms: u64,
    energy_cost: u64,
    ctx: &mut TxContext,
): Recipe {
    assert!(vector::length(&inputs) > 0, E_RECIPE_EMPTY_INPUTS);
    assert!(output.quantity > 0, E_RECIPE_ZERO_QUANTITY);
    assert!(base_duration_ms > 0, E_INVALID_RECIPE);
    assert!(energy_cost > 0, E_INVALID_RECIPE);
    // Validate each input has quantity > 0
    let mut i = 0;
    while (i < vector::length(&inputs)) {
        assert!(vector::borrow(&inputs, i).quantity > 0, E_RECIPE_ZERO_QUANTITY);
        i = i + 1;
    };
    Recipe {
        id: object::new(ctx),
        name,
        inputs,
        output,
        base_duration_ms,
        energy_cost,
        creator: tx_context::sender(ctx),
    }
}

// === Accessors ===
public fun name(r: &Recipe): String { r.name }
public fun inputs(r: &Recipe): &vector<MaterialRequirement> { &r.inputs }
public fun output(r: &Recipe): &MaterialOutput { &r.output }
public fun base_duration_ms(r: &Recipe): u64 { r.base_duration_ms }
public fun energy_cost(r: &Recipe): u64 { r.energy_cost }
public fun creator(r: &Recipe): address { r.creator }

public fun req_item_type_id(req: &MaterialRequirement): u32 { req.item_type_id }
public fun req_quantity(req: &MaterialRequirement): u64 { req.quantity }
public fun output_item_type_id(out: &MaterialOutput): u32 { out.item_type_id }
public fun output_quantity(out: &MaterialOutput): u64 { out.quantity }

/// Check if a given item_type_id is in the recipe inputs
public fun has_input_type(r: &Recipe, item_type_id: u32): bool {
    let mut i = 0;
    while (i < vector::length(&r.inputs)) {
        if (vector::borrow(&r.inputs, i).item_type_id == item_type_id) {
            return true
        };
        i = i + 1;
    };
    false
}
```

- [ ] **Step 5: Run tests — all pass**

Run: `cd packages/industrial_core && sui move test`
Expected: 5 tests PASS

- [ ] **Step 6: Commit**

```bash
git add packages/industrial_core/
git commit -m "feat(core): add recipe module with validation and tests"
```

---

### Task 2: Blueprint Module (BPO + BPC)

**Files:**
- Create: `packages/industrial_core/sources/blueprint.move`
- Create: `packages/industrial_core/tests/blueprint_tests.move`

- [ ] **Step 1: Write blueprint tests**

```move
// tests/blueprint_tests.move
#[test_only]
module industrial_core::blueprint_tests;

use industrial_core::recipe;
use industrial_core::blueprint;

fun make_test_recipe(ctx: &mut TxContext): recipe::Recipe {
    recipe::create_recipe(
        b"Test Recipe".to_string(),
        vector[recipe::new_material_req(101, 100)],
        recipe::new_material_output(201, 1),
        60_000,
        50,
        ctx,
    )
}

#[test]
fun test_mint_bpo() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let bpo = blueprint::mint_bpo(&r, 10, 15, 20, &mut ctx);
    assert!(blueprint::bpo_material_efficiency(&bpo) == 15);
    assert!(blueprint::bpo_time_efficiency(&bpo) == 20);
    assert!(blueprint::bpo_copies_minted(&bpo) == 0);
    assert!(blueprint::bpo_max_copies(&bpo) == 10);
    sui::test_utils::destroy(r);
    sui::test_utils::destroy(bpo);
}

#[test]
#[expected_failure(abort_code = blueprint::E_EFFICIENCY_OUT_OF_RANGE)]
fun test_mint_bpo_me_too_high() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let bpo = blueprint::mint_bpo(&r, 10, 26, 0, &mut ctx);
    sui::test_utils::destroy(r);
    sui::test_utils::destroy(bpo);
}

#[test]
fun test_mint_bpc_increments_copies() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 10, 10, 10, &mut ctx);
    let bpc = blueprint::mint_bpc(&mut bpo, 5, &mut ctx);
    assert!(blueprint::bpo_copies_minted(&bpo) == 1);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 5);
    sui::test_utils::destroy(r);
    sui::test_utils::destroy(bpo);
    sui::test_utils::destroy(bpc);
}

#[test]
#[expected_failure(abort_code = blueprint::E_BLUEPRINT_MAX_COPIES_REACHED)]
fun test_mint_bpc_exceeds_max() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 1, 10, 10, &mut ctx);
    let bpc1 = blueprint::mint_bpc(&mut bpo, 5, &mut ctx);
    let bpc2 = blueprint::mint_bpc(&mut bpo, 5, &mut ctx); // should fail
    sui::test_utils::destroy(r);
    sui::test_utils::destroy(bpo);
    sui::test_utils::destroy(bpc1);
    sui::test_utils::destroy(bpc2);
}

#[test]
fun test_use_bpc_decrements() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 15, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 3, &mut ctx);
    let (recipe_id, me, te) = blueprint::use_bpc(&mut bpc);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 2);
    assert!(me == 10);
    assert!(te == 15);
    sui::test_utils::destroy(r);
    sui::test_utils::destroy(bpo);
    sui::test_utils::destroy(bpc);
}

#[test]
fun test_destroy_empty_bpc() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 10, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 1, &mut ctx);
    let _ = blueprint::use_bpc(&mut bpc);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 0);
    blueprint::destroy_empty_bpc(bpc);
    sui::test_utils::destroy(r);
    sui::test_utils::destroy(bpo);
}

#[test]
#[expected_failure(abort_code = blueprint::E_BLUEPRINT_NO_USES_LEFT)]
fun test_use_bpc_zero_uses_fails() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 10, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 1, &mut ctx);
    let _ = blueprint::use_bpc(&mut bpc);
    let _ = blueprint::use_bpc(&mut bpc); // should fail
    sui::test_utils::destroy(r);
    sui::test_utils::destroy(bpo);
    sui::test_utils::destroy(bpc);
}
```

- [ ] **Step 2: Run tests — expect compile error**

Run: `cd packages/industrial_core && sui move test`
Expected: FAIL — `blueprint` module doesn't exist

- [ ] **Step 3: Implement blueprint.move**

Key implementation points:
- `BlueprintOriginal` with `key, store` abilities
- `BlueprintCopy` with `key, store` abilities
- `mint_bpo`: assert ME <= 25 && TE <= 25
- `mint_bpc`: assert max_copies == 0 || copies_minted < max_copies, increment copies_minted
- `use_bpc`: assert uses_remaining > 0, decrement, return (recipe_id, ME, TE)
- `destroy_empty_bpc`: assert uses_remaining == 0, delete
- All accessors as `public fun`

- [ ] **Step 4: Run tests — all pass**

Run: `cd packages/industrial_core && sui move test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add packages/industrial_core/sources/blueprint.move packages/industrial_core/tests/blueprint_tests.move
git commit -m "feat(core): add blueprint module with BPO/BPC lifecycle"
```

---

### Task 3: ProductionLine Module

**Files:**
- Create: `packages/industrial_core/sources/production_line.move`
- Create: `packages/industrial_core/tests/production_line_tests.move`
- Create: `packages/industrial_core/sources/mock_fuel.move`

- [ ] **Step 1: Write production line tests**

Core tests to write:
- `test_create_production_line`: creates shared object with correct initial state
- `test_authorize_operator`: owner can add, non-owner fails
- `test_max_operators_exceeded`: fails at 11th operator
- `test_deposit_materials_valid_item`: succeeds for recipe input items
- `test_deposit_materials_invalid_item`: fails for non-recipe items (E_INVALID_ITEM_TYPE)
- `test_start_production_success`: deducts materials + fuel, sets status
- `test_start_production_insufficient_materials`: fails
- `test_start_production_insufficient_fuel`: fails
- `test_start_production_recipe_mismatch`: fails
- `test_complete_production_success`: adds to output buffer, sets idle
- `test_complete_production_too_early`: fails
- `test_withdraw_output_owner_only`: operator fails
- `test_efficiency_ceiling_division`: qty=1, ME=25 → actual=1 (not 0)

- [ ] **Step 2: Run tests — expect compile error**

Run: `cd packages/industrial_core && sui move test`

- [ ] **Step 3: Implement production_line.move**

Key implementation points:
- `ProductionLine` with `key` only (has Bag, no store)
- `create_production_line`: `transfer::share_object(line)`
- `authorized_operators: VecSet<address>`, MAX_OPERATORS = 10
- `require_owner(line, ctx)` and `require_owner_or_operator(line, ctx)` internal helpers
- `deposit_materials`: require_owner + validate item_type_id against recipe inputs
- `start_production`: require_owner_or_operator, efficiency uses u128 ceiling division
- `complete_production`: require_owner_or_operator, check Clock >= job_end
- `withdraw_output`: require_owner only
- Emit `ProductionStartedEvent` and `ProductionCompletedEvent`
- Status constants: `STATUS_IDLE=0, STATUS_RUNNING=1, STATUS_PAUSED=2`

- [ ] **Step 4: Implement mock_fuel.move**

```move
module industrial_core::mock_fuel;

use industrial_core::production_line::{Self, ProductionLine};

/// Demo only — bypass owner check to deposit free fuel.
/// Uses public(package) internal fn to skip auth.
/// ⚠ Must be removed or gated before mainnet.
public entry fun mock_deposit_fuel(
    line: &mut ProductionLine,
    amount: u64,
) {
    production_line::add_fuel_internal(line, amount); // public(package) fn, no auth
}
```

Note: `production_line` 需要額外提供 `public(package) fun add_fuel_internal(line, amount)` 供 mock 使用，不做 owner check。正式的 `deposit_fuel` 仍保留 owner check。

- [ ] **Step 5: Implement `start_production_with_lease` + BPC production path**

在 `production_line.move` 中新增：

```move
/// 承租方使用租來的 BPO 生產
public fun start_production_with_lease(
    line: &mut ProductionLine,
    recipe: &Recipe,
    lease: &LeaseAgreement,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    require_owner_or_operator(line, ctx);
    assert!(tx_context::sender(ctx) == lease::lessee(lease), E_NOT_LESSEE);
    let bpo = lease::borrow_bpo(lease);
    start_production_internal(line, recipe, blueprint::bpo_recipe_id(bpo),
        blueprint::bpo_material_efficiency(bpo), blueprint::bpo_time_efficiency(bpo), clock, ctx);
}

/// 使用 BPC 的效率值生產（BPC 的 use_bpc 在 PTB 中先呼叫，取得 ME/TE 後傳入）
public fun start_production_with_efficiency(
    line: &mut ProductionLine,
    recipe: &Recipe,
    me: u8,
    te: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    require_owner_or_operator(line, ctx);
    start_production_internal(line, recipe, object::id(recipe), me, te, clock, ctx);
}

/// 內部共用邏輯：效率計算 + 扣料 + 設定狀態
fun start_production_internal(
    line: &mut ProductionLine,
    recipe: &Recipe,
    expected_recipe_id: ID,
    me: u8, te: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(object::id(recipe) == line.recipe_id, E_RECIPE_BLUEPRINT_MISMATCH);
    assert!(line.status == STATUS_IDLE, E_PRODUCTION_LINE_BUSY);
    // ceiling division with u128
    // deduct materials, deduct fuel, set timestamps, emit event
}
```

Tests to add:
- `test_start_production_with_lease_by_lessee`: succeeds
- `test_start_production_with_lease_by_non_lessee`: fails E_NOT_LESSEE
- `test_start_production_with_bpc_efficiency`: use_bpc → start_production_with_efficiency

- [ ] **Step 6: Add `revoke_operator` function**

```move
public entry fun revoke_operator(
    line: &mut ProductionLine,
    operator: address,
    ctx: &mut TxContext,
) {
    require_owner(line, ctx);
    vec_set::remove(&mut line.authorized_operators, &operator);
}
```

- [ ] **Step 7: Run tests — all pass**

Run: `cd packages/industrial_core && sui move test`

- [ ] **Step 6: Commit**

```bash
git add packages/industrial_core/sources/production_line.move packages/industrial_core/sources/mock_fuel.move packages/industrial_core/tests/production_line_tests.move
git commit -m "feat(core): add production line with shared object + auth matrix"
```

---

### Task 4: Trigger Engine Module

**Files:**
- Create: `packages/industrial_core/sources/trigger_engine.move`
- Create: `packages/industrial_core/tests/trigger_engine_tests.move`

- [ ] **Step 1: Write trigger engine tests**

Core tests:
- `test_create_trigger_rule_by_owner`: succeeds
- `test_create_trigger_rule_by_non_owner`: fails E_NOT_OWNER
- `test_evaluate_inventory_below_threshold`: returns true
- `test_evaluate_inventory_above_threshold`: returns false
- `test_evaluate_missing_bag_key`: returns true (quantity=0 < threshold)
- `test_evaluate_disabled_rule`: returns false
- `test_evaluate_cooldown_active`: returns false
- `test_execute_trigger_success`: starts production + updates last_triggered
- `test_execute_trigger_line_mismatch`: fails E_TRIGGER_LINE_MISMATCH

- [ ] **Step 2: Run tests — expect fail**

- [ ] **Step 3: Implement trigger_engine.move**

Key points:
- `TriggerRule` with `key` only (no store)
- `create_trigger_rule`: takes `&ProductionLine`, asserts sender == owner
- `toggle_trigger(rule: &mut TriggerRule, enabled: bool, ctx)`: assert sender == rule creator or line owner
- `evaluate_trigger`: pure function, uses `bag::contains` for missing key safety
- `execute_trigger`: re-evaluates on-chain, calls production_line::start_production logic, emits TriggerFiredEvent
- Cooldown check: `clock_ms >= last_triggered + cooldown_ms`

- [ ] **Step 4: Run tests — all pass**

- [ ] **Step 5: Commit**

```bash
git add packages/industrial_core/sources/trigger_engine.move packages/industrial_core/tests/trigger_engine_tests.move
git commit -m "feat(core): add trigger engine with cooldown + safety checks"
```

---

### Task 5: Core Integration Tests

**Files:**
- Create: `packages/industrial_core/tests/integration_tests.move`

- [ ] **Step 1: Write integration test: full production cycle**

```
test_full_production_cycle:
  1. create_recipe (inputs: [ore x100], output: hull x1)
  2. mint_bpo (ME=10, TE=10)
  3. create_production_line
  4. deposit_materials (ore, 100)
  5. deposit_fuel (50)
  6. start_production (with Clock)
  7. advance clock past job_end
  8. complete_production
  9. assert output_buffer has hull x1
  10. withdraw_output
```

- [ ] **Step 2: Write integration test: trigger auto-production**

```
test_trigger_auto_production:
  1. setup recipe + BPO + production line
  2. deposit materials + fuel
  3. create_trigger_rule (inventory_below, threshold=5, target=hull)
  4. evaluate_trigger → true (output buffer empty = 0 < 5)
  5. execute_trigger → production starts
  6. assert line.status == RUNNING
```

- [ ] **Step 3: Write integration test: BPC production flow**

```
test_bpc_production_flow:
  1. create_recipe + mint_bpo + mint_bpc(uses=2)
  2. create_production_line + deposit materials + fuel
  3. use_bpc → get (recipe_id, me, te)
  4. start_production_with_efficiency(line, recipe, me, te, clock)
  5. complete_production
  6. assert uses_remaining == 1
  7. use_bpc again → start_production_with_efficiency
  8. complete_production
  9. assert uses_remaining == 0
  10. destroy_empty_bpc (should succeed)
```

Note: Cross-package integration tests (work_order lifecycle, lease flow) 無法在 Move 單元測試中實現（跨 package dependency）。這些測試將在 Task 19 (E2E) 中使用 Sui CLI + TypeScript 腳本驗證：
- `test_work_order_full_lifecycle`: CLI 建單 → 接單 → 交付 → 驗收
- `test_lease_production_flow`: CLI 建租約 → start_production_with_lease → return_lease

- [ ] **Step 4: Run all tests**

Run: `cd packages/industrial_core && sui move test`
Expected: All unit + integration tests pass

- [ ] **Step 5: Run build check**

Run: `cd packages/industrial_core && sui move build`
Expected: Build successful

- [ ] **Step 6: Commit**

```bash
git add packages/industrial_core/tests/integration_tests.move
git commit -m "test(core): add integration tests for production cycle, trigger, and BPC flow"
```

---

## Phase 2: work_order Package

### Task 6: WorkOrder Module

**Files:**
- Create: `packages/work_order/Move.toml`
- Create: `packages/work_order/sources/work_order.move`
- Create: `packages/work_order/tests/work_order_tests.move`

- [ ] **Step 1: Create Move.toml with dependency on industrial_core**

```toml
[package]
name = "work_order"
edition = "2024.beta"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
industrial_core = { local = "../industrial_core" }

[addresses]
work_order = "0x0"
```

- [ ] **Step 2: Write work order tests**

Core tests:
- `test_create_work_order_with_escrow`: escrowed balance matches coin value
- `test_create_order_below_min_escrow`: fails E_INSUFFICIENT_ESCROW
- `test_create_order_deadline_too_far`: fails E_DEADLINE_TOO_FAR
- `test_accept_work_order`: status changes, acceptor set
- `test_accept_already_accepted`: fails E_ORDER_ALREADY_ACCEPTED
- `test_deliver_correct`: quantity_delivered increments
- `test_deliver_wrong_type`: fails E_DELIVERY_TYPE_MISMATCH
- `test_deliver_exceeds_quantity`: fails E_DELIVERY_QUANTITY_EXCEEDS
- `test_complete_releases_escrow`: issuer completes, acceptor gets SUI
- `test_complete_by_non_issuer`: fails E_NOT_ISSUER
- `test_cancel_before_accept`: full refund to issuer
- `test_cancel_after_accept`: fails (can't cancel accepted order)
- `test_cancel_expired_not_accepted`: full refund
- `test_cancel_expired_accepted`: 90/10 split

- [ ] **Step 3: Run tests — expect fail**

- [ ] **Step 4: Implement work_order.move**

Key points:
- `WorkOrder` with `key` only (Balance<SUI> blocks store)
- `WorkOrderBoard` with `key` only, uses `Table<ID, bool>`
- `init`: creates shared WorkOrderBoard
- `create_work_order`: assert MIN_ESCROW, MAX_DEADLINE, share_object(order)
- `deliver_work_order`: set `delivered_at` when fully delivered
- `auto_complete_work_order`: check delivered_at + 72h
- `auto_complete_work_order`: assert sender == acceptor, status == DELIVERED, clock >= delivered_at + 72h
- `cancel_work_order`: assert sender == issuer, status == OPEN, full refund, remove from board
- `cancel_expired_order`: 90/10 split logic with `balance::split`
- All events emitted at state transitions (Created, Accepted, Completed, Cancelled)
- Named status constants (STATUS_OPEN=0 ... STATUS_CANCELLED=5)

- [ ] **Step 5: Run tests — all pass**

- [ ] **Step 6: Run build**

Run: `cd packages/work_order && sui move build`

- [ ] **Step 7: Commit**

```bash
git add packages/work_order/
git commit -m "feat(work_order): add work order lifecycle with escrow + auto-complete"
```

---

### Task 7: Fleet Command Integration

**Files:**
- Create: `packages/work_order/sources/fleet_integration.move`
- Create: `packages/work_order/tests/fleet_integration_tests.move`

- [ ] **Step 1: Write fleet integration tests**

- `test_create_order_from_damage_report`: auto-sets priority=critical
- `test_damage_report_fields_preserved`: source_event stored correctly

- [ ] **Step 2: Implement fleet_integration.move**

`create_order_from_damage_report`: wraps `create_work_order` with DamageReport injection and priority=critical auto-set.

- [ ] **Step 3: Run tests — all pass**

- [ ] **Step 4: Commit**

```bash
git add packages/work_order/sources/fleet_integration.move packages/work_order/tests/fleet_integration_tests.move
git commit -m "feat(work_order): add fleet command damage report integration"
```

---

## Phase 3: marketplace Package

### Task 8: Marketplace Module (BPO/BPC Buy/Sell)

**Files:**
- Create: `packages/marketplace/Move.toml`
- Create: `packages/marketplace/sources/marketplace.move`
- Create: `packages/marketplace/tests/marketplace_tests.move`

- [ ] **Step 1: Create Move.toml**

```toml
[package]
name = "marketplace"
edition = "2024.beta"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
industrial_core = { local = "../industrial_core" }

[addresses]
marketplace = "0x0"
```

- [ ] **Step 2: Write marketplace tests**

Core tests:
- `test_init_creates_shared_marketplace`: verify shared object exists
- `test_list_bpo_wraps_object`: BPO inside BpoListing
- `test_list_below_min_price`: fails E_LISTING_PRICE_TOO_LOW
- `test_buy_bpo_fee_split`: seller gets price-fee, collector gets fee
- `test_buy_bpo_min_fee_1_mist`: fee = max(1, computed)
- `test_buy_bpo_overpayment_returns_change`: buyer pays 10 gets 5 back
- `test_delist_bpo_by_seller`: returns BPO
- `test_delist_bpo_by_non_seller`: fails E_NOT_SELLER
- `test_list_buy_bpc`: same flow for BPC

- [ ] **Step 3: Implement marketplace.move**

Key points:
- `init`: create MarketplaceAdminCap (owned by deployer) + Marketplace (shared)
- `update_fee(market, _cap: &MarketplaceAdminCap, new_bps)`: admin-only fee update
- `withdraw_fees(market, _cap: &MarketplaceAdminCap, ctx) → Coin<SUI>`: admin extracts collected fees
- `BpoListing` / `BpcListing` wrap actual blueprint objects (owned by seller, transferred by value on buy)
- `buy_bpo`: use `coin::split` for exact payment, return change via `transfer::public_transfer`
- Fee: `max(1, price * fee_bps / 10000)` — use `std::u64::max`
- All events emitted

- [ ] **Step 4: Run tests — all pass**

- [ ] **Step 5: Commit**

```bash
git add packages/marketplace/
git commit -m "feat(marketplace): add blueprint listing/buying with fee + min price"
```

---

### Task 9: Lease Module

**Files:**
- Create: `packages/marketplace/sources/lease.move`
- Create: `packages/marketplace/tests/lease_tests.move`

- [ ] **Step 1: Write lease tests**

- `test_create_lease_wraps_bpo`: BPO inside LeaseAgreement
- `test_return_lease_by_lessee`: BPO to lessor, deposit to lessee
- `test_return_lease_by_non_lessee`: fails E_NOT_LESSEE
- `test_forfeit_lease_by_lessor_after_expiry`: BPO + deposit to lessor
- `test_forfeit_lease_before_expiry`: fails E_LEASE_NOT_EXPIRED
- `test_forfeit_by_non_lessor`: fails E_NOT_LESSOR

- [ ] **Step 2: Implement lease.move**

Key points:
- `LeaseAgreement` with `key` only (has Balance)
- `create_lease`: wrap BPO, share_object(lease)
- `return_lease`: assert sender == lessee, destroy agreement, transfer BPO to lessor
- `forfeit_lease`: assert sender == lessor + clock > expiry

- [ ] **Step 3: Run tests — all pass**

- [ ] **Step 4: Run full build for all 3 packages**

```bash
cd packages/industrial_core && sui move build
cd packages/work_order && sui move build
cd packages/marketplace && sui move build
```

- [ ] **Step 5: Commit**

```bash
git add packages/marketplace/sources/lease.move packages/marketplace/tests/lease_tests.move
git commit -m "feat(marketplace): add BPO lease with shared object + auth checks"
```

---

### Task 10: Monkey Tests (All Packages)

**Files:**
- Create: `packages/industrial_core/tests/monkey_tests.move`
- Create: `packages/work_order/tests/monkey_tests.move`
- Create: `packages/marketplace/tests/monkey_tests.move`

- [ ] **Step 1: Write industrial_core monkey tests**

From spec section 10.3:
- `test_efficiency_qty_1_me_25`: ceiling → 1
- `test_deposit_invalid_item_type`: abort E_INVALID_ITEM_TYPE
- `test_bag_missing_key_evaluate`: returns true
- `test_operator_withdraw_attempt`: abort E_NOT_OWNER

- [ ] **Step 2: Write additional industrial_core monkey tests**

- `test_lease_lessee_mint_bpc`: 承租方無法取得 &mut BPO → 不可能呼叫 mint_bpc（LeaseAgreement wrap BPO 後 BPO 不在 lessee 手中）
- `test_empty_recipe_free_production`: create_recipe(inputs=[]) → abort E_RECIPE_EMPTY_INPUTS
- `test_u64_overflow_deposit`: deposit u64::MAX when buffer has 1 → Move aborts on overflow

- [ ] **Step 3: Write work_order monkey tests**

- `test_order_infinite_deadline`: abort E_DEADLINE_TOO_FAR
- `test_zero_reward_order`: abort E_INSUFFICIENT_ESCROW
- `test_auto_complete_before_72h`: abort E_AUTO_COMPLETE_TOO_EARLY
- `test_lease_orphan_recovery`: lessor forfeit after expiry → BPO + deposit 回到 lessor

- [ ] **Step 4: Write marketplace monkey tests**

- `test_micro_price_listing`: abort E_LISTING_PRICE_TOO_LOW
- `test_buy_overpayment_change`: buyer gets change
- `test_return_lease_by_stranger`: abort E_NOT_LESSEE
- `test_forfeit_before_expiry`: abort E_LEASE_NOT_EXPIRED

Note: `test_concurrent_trigger_same_rule` 無法在 Move 單元測試中實現（Sui validator 對 shared object 做 sequential 排序）。將在 Task 19 E2E 中使用兩個並發 CLI 呼叫驗證。

- [ ] **Step 5: Run all tests across all packages**

```bash
cd packages/industrial_core && sui move test
cd packages/work_order && sui move test
cd packages/marketplace && sui move test
```

- [ ] **Step 6: Commit**

```bash
git add packages/*/tests/monkey_tests.move
git commit -m "test: add adversarial monkey tests for all packages"
```

---

## Phase 4: Off-chain Watcher Service

### Task 11: Watcher Scaffold + Config

**Files:**
- Create: `watcher/package.json`
- Create: `watcher/tsconfig.json`
- Create: `watcher/src/config.ts`
- Create: `watcher/src/index.ts`

- [ ] **Step 1: Initialize project**

```bash
cd watcher
npm init -y
npm install @mysten/sui typescript tsx dotenv
npm install -D @types/node
```

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "outDir": "dist",
    "rootDir": "src",
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

- [ ] **Step 3: Create config.ts**

```typescript
// src/config.ts
import { getFullnodeUrl } from '@mysten/sui/client';

export const config = {
  suiRpcUrl: process.env.SUI_RPC_URL || getFullnodeUrl('testnet'),
  watcherKeyPath: process.env.WATCHER_KEY_PATH || './watcher-key.json',
  packageId: process.env.PACKAGE_ID || '0x...',
  pollIntervalMs: Number(process.env.POLL_INTERVAL_MS) || 10_000,
  deadlinePollMs: Number(process.env.DEADLINE_POLL_MS) || 60_000,
};
```

- [ ] **Step 4: Create index.ts entry point (skeleton)**

```typescript
// src/index.ts
import { config } from './config';

async function main() {
  console.log('Industrial Auto OS Watcher starting...');
  console.log(`RPC: ${config.suiRpcUrl}`);
  console.log(`Package: ${config.packageId}`);
  // Listeners will be added in subsequent tasks
}

main().catch(console.error);
```

- [ ] **Step 5: Verify it runs**

Run: `cd watcher && npx tsx src/index.ts`
Expected: Prints startup message

- [ ] **Step 6: Commit**

```bash
git add watcher/
git commit -m "feat(watcher): scaffold watcher service with config"
```

---

### Task 12: TX Executor + Rule Matcher

**Files:**
- Create: `watcher/src/tx-executor.ts`
- Create: `watcher/src/rule-matcher.ts`

- [ ] **Step 1: Implement tx-executor.ts**

```typescript
// src/tx-executor.ts
import { SuiClient } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';

export class TxExecutor {
  constructor(
    private client: SuiClient,
    private keypair: Ed25519Keypair,
  ) {}

  async execute(txb: Transaction): Promise<string | null> {
    try {
      const result = await this.client.signAndExecuteTransaction({
        transaction: txb,
        signer: this.keypair,
        options: { showEffects: true },
      });
      console.log(`TX executed: ${result.digest}`);
      return result.digest;
    } catch (e) {
      console.error('TX execution failed:', e);
      return null;
    }
  }
}
```

- [ ] **Step 2: Implement rule-matcher.ts**

Rule matcher: maintains cooldown map, calls evaluate_trigger off-chain simulation, dispatches execute_trigger tx via TxExecutor. Key logic:
- in-memory `Map<string, number>` for triggered_rules cooldown
- `matchAndExecute(ruleId, lineId, ...)`: check cooldown → build PTB → executor.execute()

- [ ] **Step 3: Commit**

```bash
git add watcher/src/tx-executor.ts watcher/src/rule-matcher.ts
git commit -m "feat(watcher): add tx executor and rule matcher"
```

---

### Task 13: Listeners (Fleet CMD, Inventory, Deadline)

**Files:**
- Create: `watcher/src/listeners/fleet-cmd-listener.ts`
- Create: `watcher/src/listeners/inventory-monitor.ts`
- Create: `watcher/src/listeners/deadline-scheduler.ts`

- [ ] **Step 1: Implement fleet-cmd-listener.ts**

Uses `client.subscribeEvent()` to watch for `BattleDamageEvent` from Fleet Command package. On event: extract DamageReport fields → call rule matcher.

- [ ] **Step 2: Implement inventory-monitor.ts**

Polling loop (10s): for each watched ProductionLine, query `getObject` → read output_buffer → compare against trigger thresholds → call rule matcher.

- [ ] **Step 3: Implement deadline-scheduler.ts**

Polling loop (60s): query active WorkOrders → check if past deadline → call `cancel_expired_order` via TxExecutor.

- [ ] **Step 4: Wire up in index.ts**

```typescript
// Update src/index.ts to start all listeners
import { FleetCmdListener } from './listeners/fleet-cmd-listener';
import { InventoryMonitor } from './listeners/inventory-monitor';
import { DeadlineScheduler } from './listeners/deadline-scheduler';

async function main() {
  // ... setup client, keypair, executor
  const fleetListener = new FleetCmdListener(client, ruleMatcher);
  const inventoryMonitor = new InventoryMonitor(client, ruleMatcher, config.pollIntervalMs);
  const deadlineScheduler = new DeadlineScheduler(client, executor, config.deadlinePollMs);

  await Promise.all([
    fleetListener.start(),
    inventoryMonitor.start(),
    deadlineScheduler.start(),
  ]);
}
```

- [ ] **Step 5: Verify compilation**

Run: `cd watcher && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add watcher/src/
git commit -m "feat(watcher): add all listeners (fleet, inventory, deadline)"
```

---

## Phase 5: Frontend

### Task 14: Frontend Scaffold

**Files:**
- Create: `frontend/` (via Vite scaffold)

- [ ] **Step 1: Scaffold Vite React project**

```bash
cd /path/to/Industrial_Auto_OS
npm create vite@latest frontend -- --template react-ts
cd frontend
npm install @mysten/dapp-kit-react @mysten/sui @tanstack/react-query recharts react-router-dom
npm install -D tailwindcss @tailwindcss/vite
```

- [ ] **Step 2: Configure Tailwind**

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  plugins: [react(), tailwindcss()],
});
```

Add `@import "tailwindcss";` to `src/index.css`.

- [ ] **Step 3: Setup Sui dApp Kit**

```typescript
// src/sui-config.ts
import { createDAppKit } from '@mysten/dapp-kit-react';
import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';

const client = new SuiClient({ url: getFullnodeUrl('testnet') });

export const { DAppKitProvider, useDAppKit } = createDAppKit({
  client,
});
```

```typescript
// src/constants.ts
export const PACKAGE_ID = import.meta.env.VITE_PACKAGE_ID || '0x...';
export const CORE_PACKAGE_ID = import.meta.env.VITE_CORE_PACKAGE_ID || '0x...';
export const WORK_ORDER_BOARD_ID = import.meta.env.VITE_WORK_ORDER_BOARD_ID || '0x...';
export const MARKETPLACE_ID = import.meta.env.VITE_MARKETPLACE_ID || '0x...';
```

- [ ] **Step 4: Setup main.tsx with DAppKitProvider**

```tsx
// src/main.tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DAppKitProvider } from './sui-config';
import App from './App';
import './index.css';

const queryClient = new QueryClient();

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <DAppKitProvider>
        <App />
      </DAppKitProvider>
    </QueryClientProvider>
  </React.StrictMode>,
);
```

- [ ] **Step 5: Verify dev server starts**

Run: `cd frontend && npm run dev`
Expected: Vite dev server starts at localhost:5173

- [ ] **Step 6: Commit**

```bash
git add frontend/
git commit -m "feat(frontend): scaffold React app with dApp Kit + Tailwind"
```

---

### Task 15: PTB Builders + Custom Hooks

**Files:**
- Create: `frontend/src/lib/ptb-builders.ts`
- Create: `frontend/src/hooks/useProductionLines.ts`
- Create: `frontend/src/hooks/useWorkOrders.ts`
- Create: `frontend/src/hooks/useBlueprints.ts`
- Create: `frontend/src/hooks/useEvents.ts`

- [ ] **Step 1: Implement ptb-builders.ts**

PTB construction functions for:
- `buildStartProductionTx(lineId, recipeId, blueprintId, clockId)`
- `buildDepositAndStartTx(lineId, recipeId, blueprintId, items, fuelAmount, clockId)`
- `buildBuyBpcTx(marketId, listingId, price)`
- `buildCreateWorkOrderTx(boardId, itemType, qty, reward, deadline, priority, clockId)`
- `buildAcceptOrderTx(orderId)`
- `buildDeliverOrderTx(orderId, itemTypeId, quantity)`
- `buildCompleteOrderTx(orderId, boardId)`

Each returns a `Transaction` object ready for signing.

- [ ] **Step 2: Implement custom hooks**

`useProductionLines()`: fetch owned production lines + their status via `getOwnedObjects` + `multiGetObjects`
`useWorkOrders()`: fetch board + active orders
`useBlueprints()`: fetch owned BPOs + BPCs + listed (BpoListing) + leased (LeaseAgreement)
`useEvents()`: subscribe to package events via `subscribeEvent`

All hooks use `@tanstack/react-query` with `enabled: !!account`.

- [ ] **Step 3: Verify type check**

Run: `cd frontend && npx tsc --noEmit`

- [ ] **Step 4: Commit**

```bash
git add frontend/src/lib/ frontend/src/hooks/
git commit -m "feat(frontend): add PTB builders and data hooks"
```

---

### Task 16: Dashboard Page

**Files:**
- Create: `frontend/src/pages/Dashboard.tsx`
- Create: `frontend/src/components/ProductionLineCard.tsx`
- Create: `frontend/src/components/EventFeed.tsx`

- [ ] **Step 1: Implement ProductionLineCard**

Shows: name, status (green/yellow/grey dot), recipe, progress bar (client-side timer from `current_job_end`)

- [ ] **Step 2: Implement EventFeed**

Subscribes to all package events, renders as reverse-chronological list. Events: production started/completed, trigger fired, work order created/accepted/completed.

- [ ] **Step 3: Implement Dashboard**

Layout:
- Top row: production line cards (status overview)
- Middle: production output trend chart (Recharts)
- Bottom: event feed (real-time)

- [ ] **Step 4: Add routing in App.tsx**

```tsx
import { BrowserRouter, Routes, Route } from 'react-router-dom';
// ... routes for all 5 pages
```

- [ ] **Step 5: Verify in browser**

Run: `npm run dev`, open localhost:5173
Expected: Dashboard renders with placeholder data

- [ ] **Step 6: Commit**

```bash
git add frontend/src/pages/Dashboard.tsx frontend/src/components/ frontend/src/App.tsx
git commit -m "feat(frontend): add Dashboard page with production cards + event feed"
```

---

### Task 17: Factory Detail Page

**Files:**
- Create: `frontend/src/pages/FactoryDetail.tsx`
- Create: `frontend/src/components/CountdownTimer.tsx`

- [ ] **Step 1: Implement CountdownTimer**

Client-side timer from `current_job_end`. Uses `useEffect` + `setInterval`, no polling.

- [ ] **Step 2: Implement FactoryDetail**

Sections:
- Production status + countdown timer
- Input/output buffer tables
- Trigger rules list with enable/disable toggle
- Operator management (add/remove)
- "Deposit + Start Production" button (single PTB)

- [ ] **Step 3: Verify page**

- [ ] **Step 4: Commit**

```bash
git add frontend/src/pages/FactoryDetail.tsx frontend/src/components/CountdownTimer.tsx
git commit -m "feat(frontend): add factory detail page with countdown + triggers"
```

---

### Task 18: Orders + Blueprints + Monitor Pages

**Files:**
- Create: `frontend/src/pages/Orders.tsx`
- Create: `frontend/src/pages/Blueprints.tsx`
- Create: `frontend/src/pages/Monitor.tsx`
- Create: `frontend/src/components/WorkOrderCard.tsx`
- Create: `frontend/src/components/BlueprintCard.tsx`

- [ ] **Step 1: Implement Orders page**

Tabs: Public Board | My Orders
- Public: list open work orders from WorkOrderBoard
- My Orders: filter by issuer/acceptor == current account
- Actions: Create order, Accept, Deliver, Complete

- [ ] **Step 2: Implement Blueprints page**

Tabs: My Blueprints | Market | Leases
- My Blueprints: owned BPOs + BPCs
- Market: BpoListing + BpcListing objects
- Leases: LeaseAgreement objects (as lessor or lessee)
- Note: wrapped BPOs (in listings/leases) need separate queries

- [ ] **Step 3: Implement Monitor page**

Full event stream with filters (by event type, module). Uses `subscribeEvent` for real-time + `queryEvents` for history.

- [ ] **Step 4: Verify all pages**

Run: `npm run dev`, navigate all 5 routes
Expected: All pages render

- [ ] **Step 5: Final type check + build**

```bash
cd frontend && npx tsc --noEmit && npm run build
```

- [ ] **Step 6: Commit**

```bash
git add frontend/src/pages/ frontend/src/components/
git commit -m "feat(frontend): add orders, blueprints, and monitor pages"
```

---

## Phase 6: Deployment + Integration Test

### Task 19: Deploy to Testnet + E2E Validation

- [ ] **Step 1: Deploy industrial_core**

```bash
cd packages/industrial_core
sui client publish --gas-budget 500000000
```

Record package ID → update `watcher/src/config.ts` and `frontend/.env`

- [ ] **Step 2: Deploy work_order**

```bash
cd packages/work_order
sui client publish --gas-budget 500000000
```

Record WorkOrderBoard shared object ID.

- [ ] **Step 3: Deploy marketplace**

```bash
cd packages/marketplace
sui client publish --gas-budget 500000000
```

Record Marketplace shared object ID + AdminCap object ID.

- [ ] **Step 4: Seed demo data**

Using Sui CLI:
```bash
# Create recipe
sui client call --package $CORE_PKG --module recipe --function create_recipe ...

# Mint BPO
sui client call --package $CORE_PKG --module blueprint --function mint_bpo ...

# Create production line
sui client call --package $CORE_PKG --module production_line --function create_production_line ...

# Deposit materials + fuel
sui client call --package $CORE_PKG --module production_line --function deposit_materials ...
sui client call --package $CORE_PKG --module mock_fuel --function mock_deposit_fuel ...
```

- [ ] **Step 5: Run E2E: Start production via frontend**

1. Open frontend → Dashboard
2. Navigate to factory detail
3. Click "Start Production"
4. Verify countdown timer appears
5. Wait for completion → verify output in buffer

- [ ] **Step 6: Run E2E: Work order flow**

1. Create work order (frontend)
2. Accept work order (different account)
3. Deliver → Complete → Verify escrow released

- [ ] **Step 7: Run E2E: Watcher auto-trigger**

1. Set trigger rule on production line
2. Start watcher service
3. Verify watcher detects inventory below threshold
4. Verify auto-production starts

- [ ] **Step 8: Create .env.example files (never commit actual .env)**

```bash
# watcher/.env.example
SUI_RPC_URL=https://fullnode.testnet.sui.io:443
WATCHER_KEY_PATH=./watcher-key.json
PACKAGE_ID=0x...
POLL_INTERVAL_MS=10000

# frontend/.env.example
VITE_CORE_PACKAGE_ID=0x...
VITE_WORK_ORDER_PACKAGE_ID=0x...
VITE_MARKETPLACE_PACKAGE_ID=0x...
VITE_WORK_ORDER_BOARD_ID=0x...
VITE_MARKETPLACE_ID=0x...
VITE_NETWORK=testnet
```

- [ ] **Step 9: Final commit**

```bash
git add watcher/.env.example frontend/.env.example
git commit -m "chore: add env examples for testnet deployment"
```

---

## Dependency Graph

```
Task 1 (Recipe) ─┐
Task 2 (Blueprint)─┤
Task 3 (ProdLine)──┤──→ Task 5 (Core Integration) ──→ Task 10 (Monkey)
Task 4 (Trigger)───┘
                         │
                         ├──→ Task 6 (WorkOrder) → Task 7 (Fleet) ──→ Task 10
                         │
                         └──→ Task 8 (Market) → Task 9 (Lease) ──→ Task 10
                                                                      │
                    Task 11 (Watcher Scaffold)                         │
                    Task 12 (TX Executor)    ──→ Task 13 (Listeners)   │
                                                                      │
                    Task 14 (FE Scaffold) ──→ Task 15 (Hooks)         │
                    Task 16 (Dashboard)                                │
                    Task 17 (Factory)     ──→ Task 18 (All Pages)     │
                                                                      │
                    ──────────────────→ Task 19 (Deploy + E2E) ◀──────┘
```

**Parallelism:**
- Tasks 1→2→3→4 are sequential（each builds on prior module）
- Tasks 6-7 and 8-9 can run **in parallel** after Task 5（independent packages）
- Tasks 11-13 and 14-18 can run **in parallel**（watcher and frontend are independent）
- Task 10（monkey tests）可在 Phase 2+3 完成後跑
- Task 19 requires all prior tasks

**Key additions from review:**
- Task 3 now includes `start_production_with_lease`, `start_production_with_efficiency`, `revoke_operator`
- Task 4 now includes `toggle_trigger`
- Task 5 adds BPC production flow integration test
- Task 6 adds `auto_complete_work_order` + `cancel_work_order`
- Task 8 adds `update_fee` + `withdraw_fees`
- Task 10 adds 4 additional monkey tests
- Cross-package integration tests deferred to Task 19 E2E（Move 單元測試不支援跨 package）

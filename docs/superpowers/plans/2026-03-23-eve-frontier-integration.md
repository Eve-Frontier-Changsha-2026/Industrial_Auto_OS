# EVE Frontier Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Industrial Auto OS with EVE Frontier's Smart Storage Unit (inventory I/O) and Smart Gate (factory access control) via the typed witness pattern.

**Architecture:** New `eve_integration` Move package imports EVE's `world` contracts + existing Industrial Auto OS packages (read-only). Three modules: `eve_bridge` (SSU adapter + ItemRegistry), `factory_access` (AccessPass + Gate permits), `events` (all custom events). Frontend gets 4 new panes + PTB builders. Watcher gets 5 new rules.

**Tech Stack:** Move 2024 edition, @mysten/sui v2, React 18, Vite, Vitest, YAML config

**Spec:** `docs/superpowers/specs/2026-03-23-eve-frontier-integration-design.md`

---

## File Structure

### New files (Move)
```
packages/eve_integration/
├── Move.toml                         # deps: Sui, world, industrial_core, marketplace, work_order
├── sources/
│   ├── eve_bridge.move               # IndustrialAuth witness, GlobalRegistry, SSU adapter
│   ├── factory_access.move           # AccessRegistry, AccessPass, Gate permits
│   └── events.move                   # All integration events
└── tests/
    ├── bridge_tests.move             # Registry + type conversion tests
    ├── access_tests.move             # AccessPass lifecycle tests
    └── monkey_tests.move             # Extreme edge case tests
```

### New files (Frontend)
```
frontend/src/lib/ptb/eveBridge.ts          # SSU + registry PTB builders
frontend/src/lib/ptb/factoryAccess.ts      # AccessPass + Gate permit PTB builders
frontend/src/panes/SSUInventory.tsx         # SSU inventory display
frontend/src/panes/SSUInventory.module.css
frontend/src/panes/GateAccess.tsx           # AccessPass management
frontend/src/panes/GateAccess.module.css
frontend/src/panes/ItemMapping.tsx          # GlobalRegistry + FactoryOverride
frontend/src/panes/ItemMapping.module.css
frontend/src/panes/LinkAssembly.tsx         # Register extension on SSU/Gate
frontend/src/panes/LinkAssembly.module.css
```

### New files (Watcher)
```
watcher/src/rules/auto-produce-from-ssu.ts
watcher/src/rules/auto-collect-to-ssu.ts
watcher/src/rules/auto-grant-access.ts
watcher/src/rules/auto-revoke-access.ts
watcher/src/rules/sync-registry.ts
```

### Modified files
```
frontend/src/lib/types.ts                  # Add EVE integration types
frontend/src/lib/errors.ts                 # Add error codes 1001-1006, 2001-2012
frontend/src/config/paneRegistry.ts         # Register 4 new panes
frontend/src/App.tsx                       # (if pane registry auto-loads, no change needed)
frontend/.env                              # Add VITE_PKG_EVE_INTEGRATION, VITE_GLOBAL_REGISTRY, VITE_ACCESS_REGISTRY
watcher/src/index.ts                       # Register 5 new rule handlers
watcher/src/types.ts                       # Add EVE integration signal types
watcher/config.example.yaml               # Add eve_integration config section
```

---

## Task 1: Scaffold eve_integration Move package

**Files:**
- Create: `packages/eve_integration/Move.toml`
- Create: `packages/eve_integration/sources/events.move`

- [ ] **Step 1: Create Move.toml**

```toml
[package]
name = "eve_integration"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
world = { git = "https://github.com/evefrontier/world-contracts.git", subdir = "contracts/world", rev = "main" }
industrial_core = { local = "../industrial_core" }
marketplace = { local = "../marketplace" }
work_order = { local = "../work_order" }

[addresses]
eve_integration = "0x0"
```

Note: `world` rev should be pinned to a specific commit hash before deployment. Use `main` for initial development; run `git ls-remote https://github.com/evefrontier/world-contracts.git HEAD` to get the hash.

- [ ] **Step 2: Create events.move with all event structs**

```move
module eve_integration::events {
    use std::string::String;

    // === SSU Bridge Events ===
    public struct SSUWithdrawEvent has copy, drop {
        ssu_id: ID,
        factory_id: ID,
        eve_type_id: u64,
        material_id: String,
        quantity: u32,
        operator: address,
    }

    public struct SSUDepositEvent has copy, drop {
        ssu_id: ID,
        factory_id: ID,
        eve_type_id: u64,
        material_id: String,
        quantity: u32,
        operator: address,
    }

    public struct ProductionFromSSUEvent has copy, drop {
        ssu_id: ID,
        factory_id: ID,
        recipe_id: ID,
        input_count: u64,
    }

    public struct CollectToSSUEvent has copy, drop {
        ssu_id: ID,
        factory_id: ID,
        output_count: u64,
    }

    // === Access Events ===
    public struct AccessGrantedEvent has copy, drop {
        pass_id: ID,
        factory_id: ID,
        holder: address,
        pass_type: u8,
        expires_at: Option<u64>,
    }

    public struct AccessRevokedEvent has copy, drop {
        pass_id: ID,
        factory_id: ID,
        holder: address,
        reason: String,
    }

    public struct PermitIssuedEvent has copy, drop {
        permit_id: ID,
        factory_id: ID,
        character_address: address,
        source_gate_id: ID,
        dest_gate_id: ID,
        expires_at: u64,
    }

    // === Registry Events ===
    public struct GlobalMappingAddedEvent has copy, drop {
        eve_type_id: u64,
        material_id: String,
    }

    public struct GlobalMappingRemovedEvent has copy, drop {
        eve_type_id: u64,
        material_id: String,
    }

    public struct FactoryMappingDisabledEvent has copy, drop {
        factory_id: ID,
        eve_type_id: u64,
    }

    public struct FactoryMappingEnabledEvent has copy, drop {
        factory_id: ID,
        eve_type_id: u64,
    }

    // === Public constructors for sibling modules ===
    public fun new_ssu_withdraw_event(
        ssu_id: ID, factory_id: ID, eve_type_id: u64,
        material_id: String, quantity: u32, operator: address,
    ): SSUWithdrawEvent {
        SSUWithdrawEvent { ssu_id, factory_id, eve_type_id, material_id, quantity, operator }
    }

    public fun new_ssu_deposit_event(
        ssu_id: ID, factory_id: ID, eve_type_id: u64,
        material_id: String, quantity: u32, operator: address,
    ): SSUDepositEvent {
        SSUDepositEvent { ssu_id, factory_id, eve_type_id, material_id, quantity, operator }
    }

    public fun new_access_granted_event(
        pass_id: ID, factory_id: ID, holder: address, pass_type: u8, expires_at: Option<u64>,
    ): AccessGrantedEvent {
        AccessGrantedEvent { pass_id, factory_id, holder, pass_type, expires_at }
    }

    public fun new_access_revoked_event(
        pass_id: ID, factory_id: ID, holder: address, reason: String,
    ): AccessRevokedEvent {
        AccessRevokedEvent { pass_id, factory_id, holder, reason }
    }

    public fun new_permit_issued_event(
        permit_id: ID, factory_id: ID, character_address: address,
        source_gate_id: ID, dest_gate_id: ID, expires_at: u64,
    ): PermitIssuedEvent {
        PermitIssuedEvent { permit_id, factory_id, character_address, source_gate_id, dest_gate_id, expires_at }
    }

    public fun new_global_mapping_added(eve_type_id: u64, material_id: String): GlobalMappingAddedEvent {
        GlobalMappingAddedEvent { eve_type_id, material_id }
    }

    public fun new_global_mapping_removed(eve_type_id: u64, material_id: String): GlobalMappingRemovedEvent {
        GlobalMappingRemovedEvent { eve_type_id, material_id }
    }

    public fun new_factory_mapping_disabled(factory_id: ID, eve_type_id: u64): FactoryMappingDisabledEvent {
        FactoryMappingDisabledEvent { factory_id, eve_type_id }
    }

    public fun new_factory_mapping_enabled(factory_id: ID, eve_type_id: u64): FactoryMappingEnabledEvent {
        FactoryMappingEnabledEvent { factory_id, eve_type_id }
    }
}
```

- [ ] **Step 3: Verify world dependency resolves**

Run: `cd packages/eve_integration && sui move build 2>&1 | head -30`

Expected: Dependency resolution starts (may fail on missing modules since eve_bridge/factory_access not yet created — that's OK). If `world` dependency fails to resolve, check git URL and rev.

If dependency resolution fails due to conflicting Sui framework versions between `world` and `industrial_core`, check both `Move.toml` files' Sui dependency rev and align them.

- [ ] **Step 4: Commit**

```bash
git add packages/eve_integration/
git commit -m "feat(eve_integration): scaffold package with events module"
```

---

## Task 2: Implement eve_bridge.move — GlobalRegistry + ItemMapping

**Files:**
- Create: `packages/eve_integration/sources/eve_bridge.move`
- Create: `packages/eve_integration/tests/bridge_tests.move`

- [ ] **Step 1: Write bridge_tests.move — registry tests**

```move
#[test_only]
module eve_integration::bridge_tests {
    use std::string;
    use sui::test_scenario;
    use eve_integration::eve_bridge::{Self, GlobalRegistry, RegistryAdminCap};

    #[test]
    fun test_init_creates_registry_and_cap() {
        let mut scenario = test_scenario::begin(@0xADMIN);
        {
            eve_bridge::init_for_testing(scenario.ctx());
        };
        scenario.next_tx(@0xADMIN);
        {
            assert!(test_scenario::has_most_recent_shared<GlobalRegistry>());
            assert!(test_scenario::has_most_recent_for_address<RegistryAdminCap>(@0xADMIN));
        };
        scenario.end();
    }

    #[test]
    fun test_add_and_resolve_global_mapping() {
        let mut scenario = test_scenario::begin(@0xADMIN);
        {
            eve_bridge::init_for_testing(scenario.ctx());
        };
        scenario.next_tx(@0xADMIN);
        {
            let mut registry = scenario.take_shared<GlobalRegistry>();
            let cap = scenario.take_from_sender<RegistryAdminCap>();

            eve_bridge::add_global_mapping(
                &mut registry, &cap, 12001, string::utf8(b"tritanium"),
            );

            let result = eve_bridge::resolve_eve_to_industrial(&registry, 12001);
            assert!(result.is_some());
            assert!(*result.borrow() == string::utf8(b"tritanium"));

            let reverse = eve_bridge::resolve_industrial_to_eve(&registry, string::utf8(b"tritanium"));
            assert!(reverse.is_some());
            assert!(*reverse.borrow() == 12001);

            scenario.return_to_sender(cap);
            test_scenario::return_shared(registry);
        };
        scenario.end();
    }

    #[test]
    fun test_remove_global_mapping() {
        let mut scenario = test_scenario::begin(@0xADMIN);
        {
            eve_bridge::init_for_testing(scenario.ctx());
        };
        scenario.next_tx(@0xADMIN);
        {
            let mut registry = scenario.take_shared<GlobalRegistry>();
            let cap = scenario.take_from_sender<RegistryAdminCap>();

            eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));
            eve_bridge::remove_global_mapping(&mut registry, &cap, 12001);

            let result = eve_bridge::resolve_eve_to_industrial(&registry, 12001);
            assert!(result.is_none());

            scenario.return_to_sender(cap);
            test_scenario::return_shared(registry);
        };
        scenario.end();
    }

    #[test]
    fun test_factory_override_disables_mapping() {
        let mut scenario = test_scenario::begin(@0xADMIN);
        {
            eve_bridge::init_for_testing(scenario.ctx());
        };
        scenario.next_tx(@0xADMIN);
        {
            let mut registry = scenario.take_shared<GlobalRegistry>();
            let cap = scenario.take_from_sender<RegistryAdminCap>();

            eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));

            let factory_id = object::id_from_address(@0xFACTORY);
            eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 12001);

            // Global still works
            let global_result = eve_bridge::resolve_eve_to_industrial(&registry, 12001);
            assert!(global_result.is_some());

            // Factory-specific is disabled
            let factory_result = eve_bridge::resolve_eve_to_industrial_for_factory(
                &registry, factory_id, 12001,
            );
            assert!(factory_result.is_none());

            scenario.return_to_sender(cap);
            test_scenario::return_shared(registry);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = eve_bridge::E_NOT_IN_GLOBAL)]
    fun test_disable_nonexistent_mapping_fails() {
        let mut scenario = test_scenario::begin(@0xADMIN);
        {
            eve_bridge::init_for_testing(scenario.ctx());
        };
        scenario.next_tx(@0xADMIN);
        {
            let mut registry = scenario.take_shared<GlobalRegistry>();
            let cap = scenario.take_from_sender<RegistryAdminCap>();
            let factory_id = object::id_from_address(@0xFACTORY);

            // Try to disable a mapping that doesn't exist globally
            eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 99999);

            scenario.return_to_sender(cap);
            test_scenario::return_shared(registry);
        };
        scenario.end();
    }
}
```

- [ ] **Step 2: Implement eve_bridge.move — structs, init, registry management**

```move
module eve_integration::eve_bridge {
    use std::string::String;
    use sui::dynamic_field;
    use sui::event;
    use sui::vec_set::{Self, VecSet};
    use sui::table::{Self, Table};
    use eve_integration::events;

    // === Error Codes ===
    const E_NOT_AUTHORIZED: u64 = 1001;
    const E_SSU_OFFLINE: u64 = 1002;
    const E_MAPPING_NOT_FOUND: u64 = 1003;
    const E_NOT_IN_GLOBAL: u64 = 1004;
    const E_QUANTITY_OVERFLOW: u64 = 1005;
    const E_FACTORY_MAPPING_DISABLED: u64 = 1006;
    const E_MAPPING_ALREADY_EXISTS: u64 = 1007;

    // === Witness ===
    public struct IndustrialAuth has drop {}

    // === GlobalRegistry ===
    public struct GlobalRegistry has key {
        id: UID,
    }

    public struct RegistryAdminCap has key, store {
        id: UID,
    }

    // Dynamic field keys for mappings
    public struct EveToIndustrial has copy, drop, store { eve_type_id: u64 }
    public struct IndustrialToEve has copy, drop, store { material_id: String }

    // Factory override
    public struct FactoryOverrideKey has copy, drop, store { factory_id: ID }
    public struct FactoryOverride has store {
        disabled_types: VecSet<u64>,
    }

    // === Init ===
    fun init(ctx: &mut TxContext) {
        let registry = GlobalRegistry { id: object::new(ctx) };
        let cap = RegistryAdminCap { id: object::new(ctx) };
        transfer::share_object(registry);
        transfer::transfer(cap, ctx.sender());
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // === Admin: Global Mapping Management ===

    public fun add_global_mapping(
        registry: &mut GlobalRegistry,
        _cap: &RegistryAdminCap,
        eve_type_id: u64,
        material_id: String,
    ) {
        let eve_key = EveToIndustrial { eve_type_id };
        assert!(!dynamic_field::exists_(&registry.id, eve_key), E_MAPPING_ALREADY_EXISTS);
        dynamic_field::add(&mut registry.id, eve_key, material_id);
        dynamic_field::add(&mut registry.id, IndustrialToEve { material_id }, eve_type_id);
        event::emit(events::new_global_mapping_added(eve_type_id, material_id));
    }

    public fun remove_global_mapping(
        registry: &mut GlobalRegistry,
        _cap: &RegistryAdminCap,
        eve_type_id: u64,
    ) {
        let eve_key = EveToIndustrial { eve_type_id };
        assert!(dynamic_field::exists_(&registry.id, eve_key), E_MAPPING_NOT_FOUND);
        let material_id: String = dynamic_field::remove(&mut registry.id, eve_key);
        dynamic_field::remove<IndustrialToEve, u64>(&mut registry.id, IndustrialToEve { material_id });
        event::emit(events::new_global_mapping_removed(eve_type_id, material_id));
    }

    // === Factory Override ===

    /// Admin disables a specific eve_type_id for a factory.
    public fun disable_factory_mapping_admin(
        registry: &mut GlobalRegistry,
        _cap: &RegistryAdminCap,
        factory_id: ID,
        eve_type_id: u64,
    ) {
        // Must exist in global
        assert!(dynamic_field::exists_(&registry.id, EveToIndustrial { eve_type_id }), E_NOT_IN_GLOBAL);
        let override_key = FactoryOverrideKey { factory_id };
        if (!dynamic_field::exists_(&registry.id, override_key)) {
            dynamic_field::add(&mut registry.id, override_key, FactoryOverride {
                disabled_types: vec_set::empty(),
            });
        };
        let override_data = dynamic_field::borrow_mut<FactoryOverrideKey, FactoryOverride>(
            &mut registry.id, override_key,
        );
        override_data.disabled_types.insert(eve_type_id);
        event::emit(events::new_factory_mapping_disabled(factory_id, eve_type_id));
    }

    /// Factory owner disables a mapping for their factory.
    /// Requires proving ownership of the production line.
    public fun disable_factory_mapping(
        registry: &mut GlobalRegistry,
        line: &industrial_core::production_line::ProductionLine,
        eve_type_id: u64,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == industrial_core::production_line::owner(line), E_NOT_AUTHORIZED);
        assert!(dynamic_field::exists_(&registry.id, EveToIndustrial { eve_type_id }), E_NOT_IN_GLOBAL);
        let factory_id = object::id(line);
        let override_key = FactoryOverrideKey { factory_id };
        if (!dynamic_field::exists_(&registry.id, override_key)) {
            dynamic_field::add(&mut registry.id, override_key, FactoryOverride {
                disabled_types: vec_set::empty(),
            });
        };
        let override_data = dynamic_field::borrow_mut<FactoryOverrideKey, FactoryOverride>(
            &mut registry.id, override_key,
        );
        override_data.disabled_types.insert(eve_type_id);
        event::emit(events::new_factory_mapping_disabled(factory_id, eve_type_id));
    }

    /// Re-enable a previously disabled mapping.
    public fun enable_factory_mapping(
        registry: &mut GlobalRegistry,
        line: &industrial_core::production_line::ProductionLine,
        eve_type_id: u64,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == industrial_core::production_line::owner(line), E_NOT_AUTHORIZED);
        let factory_id = object::id(line);
        let override_key = FactoryOverrideKey { factory_id };
        assert!(dynamic_field::exists_(&registry.id, override_key), E_MAPPING_NOT_FOUND);
        let override_data = dynamic_field::borrow_mut<FactoryOverrideKey, FactoryOverride>(
            &mut registry.id, override_key,
        );
        override_data.disabled_types.remove(&eve_type_id);
        event::emit(events::new_factory_mapping_enabled(factory_id, eve_type_id));
    }

    // === Lookup Functions ===

    /// Resolve EVE type_id to Industrial material_id (global only).
    public fun resolve_eve_to_industrial(
        registry: &GlobalRegistry,
        eve_type_id: u64,
    ): Option<String> {
        let key = EveToIndustrial { eve_type_id };
        if (dynamic_field::exists_(&registry.id, key)) {
            option::some(*dynamic_field::borrow<EveToIndustrial, String>(&registry.id, key))
        } else {
            option::none()
        }
    }

    /// Resolve Industrial material_id to EVE type_id (global only).
    public fun resolve_industrial_to_eve(
        registry: &GlobalRegistry,
        material_id: String,
    ): Option<u64> {
        let key = IndustrialToEve { material_id };
        if (dynamic_field::exists_(&registry.id, key)) {
            option::some(*dynamic_field::borrow<IndustrialToEve, u64>(&registry.id, key))
        } else {
            option::none()
        }
    }

    /// Resolve with factory override check. Returns None if disabled for this factory.
    public fun resolve_eve_to_industrial_for_factory(
        registry: &GlobalRegistry,
        factory_id: ID,
        eve_type_id: u64,
    ): Option<String> {
        // Check factory override first
        let override_key = FactoryOverrideKey { factory_id };
        if (dynamic_field::exists_(&registry.id, override_key)) {
            let override_data = dynamic_field::borrow<FactoryOverrideKey, FactoryOverride>(
                &registry.id, override_key,
            );
            if (override_data.disabled_types.contains(&eve_type_id)) {
                return option::none()
            };
        };
        // Fall through to global
        resolve_eve_to_industrial(registry, eve_type_id)
    }

    /// Check if a global mapping exists.
    public fun has_global_mapping(registry: &GlobalRegistry, eve_type_id: u64): bool {
        dynamic_field::exists_(&registry.id, EveToIndustrial { eve_type_id })
    }

    // === SSU Registration (placeholder — requires world types) ===
    // These functions will be uncommented once world dependency compiles:
    //
    // public fun register_on_ssu(
    //     ssu: &mut world::storage_unit::StorageUnit,
    //     owner_cap: &world::access::OwnerCap<world::storage_unit::StorageUnit>,
    // ) {
    //     world::storage_unit::authorize_extension<IndustrialAuth>(ssu, owner_cap);
    // }
    //
    // public fun register_on_gate(
    //     gate: &mut world::gate::Gate,
    //     owner_cap: &world::access::OwnerCap<world::gate::Gate>,
    // ) {
    //     world::gate::authorize_extension<IndustrialAuth>(gate, owner_cap);
    // }

    // === SSU Operations (placeholder — requires world types) ===
    // withdraw_from_ssu, deposit_to_ssu, produce_from_ssu, collect_to_ssu
    // Implementation depends on world::storage_unit interface.
    // See spec Section 4.5 for pseudocode.
}
```

**Important:** The SSU/Gate registration and operation functions are commented out as placeholders because they depend on the `world` package's exact types (`StorageUnit`, `Gate`, `Character`, `OwnerCap`). Once the `world` dependency compiles, uncomment and adapt to the actual type paths.

- [ ] **Step 3: Build check**

Run: `cd packages/eve_integration && sui move build 2>&1 | tail -20`

Expected: Build succeeds. If `world` dependency causes compilation issues, temporarily comment out the `world` import in `Move.toml` and only build/test the registry logic (which doesn't depend on `world` types).

- [ ] **Step 4: Run tests**

Run: `cd packages/eve_integration && sui move test 2>&1 | tail -20`

Expected: All bridge_tests pass (init, add/remove mapping, factory override, error cases).

- [ ] **Step 5: Commit**

```bash
git add packages/eve_integration/sources/eve_bridge.move packages/eve_integration/tests/bridge_tests.move
git commit -m "feat(eve_integration): GlobalRegistry with two-tier item mapping"
```

---

## Task 3: Implement factory_access.move — AccessPass + AccessRegistry

**Files:**
- Create: `packages/eve_integration/sources/factory_access.move`
- Create: `packages/eve_integration/tests/access_tests.move`

- [ ] **Step 1: Write access_tests.move**

```move
#[test_only]
module eve_integration::access_tests {
    use std::string;
    use sui::test_scenario;
    use sui::clock;
    use eve_integration::factory_access::{Self, AccessRegistry, AccessPass};
    use eve_integration::eve_bridge::{Self, GlobalRegistry, RegistryAdminCap};
    use industrial_core::recipe;
    use industrial_core::blueprint;
    use industrial_core::production_line;

    // Helper: create a recipe + production line + BPO for testing
    fun setup_factory(scenario: &mut test_scenario::Scenario, owner: address) {
        scenario.next_tx(owner);
        {
            let input = recipe::new_material_req(1001, 100);
            let output = recipe::new_material_output(2001, 50);
            let r = recipe::create_recipe(
                string::utf8(b"Test Recipe"),
                vector[input], output, 60000, 10, scenario.ctx(),
            );
            transfer::public_share_object(r);
        };
        scenario.next_tx(owner);
        {
            let r = scenario.take_shared<industrial_core::recipe::Recipe>();
            let recipe_id = recipe::recipe_id(&r);
            production_line::create_production_line(
                string::utf8(b"Test Factory"), recipe_id, scenario.ctx(),
            );
            test_scenario::return_shared(r);
        };
        scenario.next_tx(owner);
        {
            let r = scenario.take_shared<industrial_core::recipe::Recipe>();
            let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
            transfer::public_transfer(bpo, owner);
            test_scenario::return_shared(r);
        };
    }

    #[test]
    fun test_claim_from_blueprint_happy_path() {
        let owner = @0xOWNER;
        let mut scenario = test_scenario::begin(owner);
        // Init registries
        {
            eve_bridge::init_for_testing(scenario.ctx());
            factory_access::init_for_testing(scenario.ctx());
        };
        setup_factory(&mut scenario, owner);
        scenario.next_tx(owner);
        {
            let mut access_reg = scenario.take_shared<AccessRegistry>();
            let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
            let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

            factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());

            test_scenario::return_shared(line);
            scenario.return_to_sender(bpo);
            test_scenario::return_shared(access_reg);
        };
        // Verify pass was created
        scenario.next_tx(owner);
        {
            assert!(test_scenario::has_most_recent_for_address<AccessPass>(owner));
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = factory_access::E_RECIPE_MISMATCH)]
    fun test_claim_from_blueprint_recipe_mismatch() {
        let owner = @0xOWNER;
        let mut scenario = test_scenario::begin(owner);
        {
            eve_bridge::init_for_testing(scenario.ctx());
            factory_access::init_for_testing(scenario.ctx());
        };
        // Create two different recipes, BPO from one, line from other
        scenario.next_tx(owner);
        {
            let input1 = recipe::new_material_req(1001, 100);
            let output1 = recipe::new_material_output(2001, 50);
            let r1 = recipe::create_recipe(
                string::utf8(b"Recipe A"), vector[input1], output1, 60000, 10, scenario.ctx(),
            );
            let input2 = recipe::new_material_req(1002, 200);
            let output2 = recipe::new_material_output(2002, 100);
            let r2 = recipe::create_recipe(
                string::utf8(b"Recipe B"), vector[input2], output2, 60000, 10, scenario.ctx(),
            );
            // BPO from recipe A
            let bpo = blueprint::mint_bpo(&r1, 10, 5, 5, scenario.ctx());
            transfer::public_transfer(bpo, owner);
            // Line from recipe B
            let r2_id = recipe::recipe_id(&r2);
            production_line::create_production_line(
                string::utf8(b"Factory B"), r2_id, scenario.ctx(),
            );
            transfer::public_share_object(r1);
            transfer::public_share_object(r2);
        };
        scenario.next_tx(owner);
        {
            let mut access_reg = scenario.take_shared<AccessRegistry>();
            let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
            let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

            // This should fail — BPO recipe != line recipe
            factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());

            test_scenario::return_shared(line);
            scenario.return_to_sender(bpo);
            test_scenario::return_shared(access_reg);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = factory_access::E_DUPLICATE_PASS)]
    fun test_duplicate_claim_fails() {
        let owner = @0xOWNER;
        let mut scenario = test_scenario::begin(owner);
        {
            eve_bridge::init_for_testing(scenario.ctx());
            factory_access::init_for_testing(scenario.ctx());
        };
        setup_factory(&mut scenario, owner);
        scenario.next_tx(owner);
        {
            let mut access_reg = scenario.take_shared<AccessRegistry>();
            let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
            let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

            factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());

            test_scenario::return_shared(line);
            scenario.return_to_sender(bpo);
            test_scenario::return_shared(access_reg);
        };
        // Try claiming again — should fail
        scenario.next_tx(owner);
        {
            let mut access_reg = scenario.take_shared<AccessRegistry>();
            let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
            let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

            factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());

            test_scenario::return_shared(line);
            scenario.return_to_sender(bpo);
            test_scenario::return_shared(access_reg);
        };
        scenario.end();
    }

    #[test]
    fun test_admin_revoke_blocks_permit() {
        let owner = @0xOWNER;
        let mut scenario = test_scenario::begin(owner);
        {
            eve_bridge::init_for_testing(scenario.ctx());
            factory_access::init_for_testing(scenario.ctx());
        };
        setup_factory(&mut scenario, owner);
        // Claim pass
        scenario.next_tx(owner);
        {
            let mut access_reg = scenario.take_shared<AccessRegistry>();
            let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
            let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

            factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());

            test_scenario::return_shared(line);
            scenario.return_to_sender(bpo);
            test_scenario::return_shared(access_reg);
        };
        // Admin revoke
        scenario.next_tx(owner);
        {
            let mut access_reg = scenario.take_shared<AccessRegistry>();
            let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
            let pass = scenario.take_from_sender<AccessPass>();
            let pass_id = object::id(&pass);

            factory_access::admin_revoke_pass(&mut access_reg, pass_id, &line, scenario.ctx());

            // Verify pass is marked revoked
            assert!(factory_access::is_pass_revoked(&access_reg, pass_id));

            scenario.return_to_sender(pass);
            test_scenario::return_shared(line);
            test_scenario::return_shared(access_reg);
        };
        scenario.end();
    }

    #[test]
    fun test_surrender_pass() {
        let owner = @0xOWNER;
        let mut scenario = test_scenario::begin(owner);
        {
            eve_bridge::init_for_testing(scenario.ctx());
            factory_access::init_for_testing(scenario.ctx());
        };
        setup_factory(&mut scenario, owner);
        scenario.next_tx(owner);
        {
            let mut access_reg = scenario.take_shared<AccessRegistry>();
            let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
            let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
            factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());
            test_scenario::return_shared(line);
            scenario.return_to_sender(bpo);
            test_scenario::return_shared(access_reg);
        };
        scenario.next_tx(owner);
        {
            let mut access_reg = scenario.take_shared<AccessRegistry>();
            let pass = scenario.take_from_sender<AccessPass>();
            factory_access::surrender_pass(&mut access_reg, pass, scenario.ctx());
            test_scenario::return_shared(access_reg);
        };
        // Verify pass is gone
        scenario.next_tx(owner);
        {
            assert!(!test_scenario::has_most_recent_for_address<AccessPass>(owner));
        };
        scenario.end();
    }

    // === Lease Claim Tests ===

    #[test]
    fun test_claim_from_lease_happy_path() {
        // Setup: create lease via marketplace, then claim pass
        // Verify: pass created with PASS_TYPE_LEASE, expires_at = lease expiry
        // Note: requires LeaseAgreement setup — may need #[test_only] helper
        // in marketplace::lease or direct struct creation in test
    }

    #[test]
    #[expected_failure(abort_code = factory_access::E_LEASE_NOT_ACTIVE)]
    fun test_claim_from_lease_inactive() {
        // Setup: create lease then return it (makes it inactive)
        // Verify: claim fails with E_LEASE_NOT_ACTIVE
    }

    #[test]
    #[expected_failure(abort_code = factory_access::E_NOT_LESSEE)]
    fun test_claim_from_lease_wrong_lessee() {
        // Setup: lease owned by user A, user B tries to claim
        // Verify: fails with E_NOT_LESSEE
    }

    // === Work Order Claim Tests ===

    #[test]
    fun test_claim_from_work_order_happy_path() {
        // Setup: create WO, accept it, then acceptor claims pass
        // Verify: pass created with PASS_TYPE_WORK_ORDER
    }

    #[test]
    #[expected_failure(abort_code = factory_access::E_NOT_ACCEPTOR)]
    fun test_claim_from_work_order_wrong_acceptor() {
        // Setup: WO accepted by user A, user B tries to claim
        // Verify: fails with E_NOT_ACCEPTOR
    }

    #[test]
    #[expected_failure(abort_code = factory_access::E_WO_NOT_ACTIVE)]
    fun test_claim_from_work_order_wrong_status() {
        // Setup: WO in OPEN status (not yet accepted)
        // Verify: fails with E_WO_NOT_ACTIVE
    }

    // === Expiry Revocation Tests ===

    #[test]
    fun test_revoke_expired_pass() {
        // Setup: create lease pass with expiry, advance clock past expiry
        // Call revoke_expired — should succeed
        // Verify: pass destroyed, unregistered from active_passes
    }

    #[test]
    #[expected_failure(abort_code = factory_access::E_NOT_YET_EXPIRED)]
    fun test_revoke_not_yet_expired() {
        // Setup: create lease pass with future expiry
        // Call revoke_expired with current clock — should fail
    }

    #[test]
    #[expected_failure(abort_code = factory_access::E_PASS_NOT_EXPIRABLE)]
    fun test_revoke_expired_on_permanent_pass() {
        // Setup: blueprint pass (expires_at = None)
        // Call revoke_expired — should fail (permanent passes can't expire)
    }
}
```

- [ ] **Step 2: Implement factory_access.move**

```move
module eve_integration::factory_access {
    use std::string::{Self, String};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use industrial_core::blueprint::{Self, BlueprintOriginal};
    use industrial_core::production_line::{Self, ProductionLine};
    use marketplace::lease::{Self, LeaseAgreement};
    use work_order::work_order::{Self, WorkOrder};
    use eve_integration::events;

    // === Error Codes ===
    const E_RECIPE_MISMATCH: u64 = 2001;
    const E_LEASE_NOT_ACTIVE: u64 = 2002;
    const E_NOT_LESSEE: u64 = 2003;
    const E_WO_NOT_ACTIVE: u64 = 2004;
    const E_NOT_ACCEPTOR: u64 = 2005;
    const E_NOT_PASS_HOLDER: u64 = 2006;
    const E_PASS_EXPIRED: u64 = 2007;
    const E_NOT_YET_EXPIRED: u64 = 2008;
    const E_FACTORY_MISMATCH: u64 = 2009;
    const E_PASS_NOT_EXPIRABLE: u64 = 2010;
    const E_DUPLICATE_PASS: u64 = 2011;
    const E_PASS_REVOKED: u64 = 2012;
    const E_NOT_AUTHORIZED: u64 = 2013;

    // === Constants ===
    const PASS_TYPE_BLUEPRINT: u8 = 0;
    const PASS_TYPE_LEASE: u8 = 1;
    const PASS_TYPE_WORK_ORDER: u8 = 2;
    const PERMIT_DURATION_MS: u64 = 3_600_000; // 1 hour

    // === AccessPass (key only — non-transferable) ===
    public struct AccessPass has key {
        id: UID,
        factory_id: ID,
        holder: address,
        pass_type: u8,
        expires_at: Option<u64>,
    }

    // === AccessRegistry (shared) ===
    public struct AccessRegistry has key {
        id: UID,
        revoked_passes: Table<ID, bool>,
        active_passes: Table<ActivePassKey, ID>,
    }

    public struct ActivePassKey has copy, drop, store {
        factory_id: ID,
        holder: address,
    }

    // === Init ===
    fun init(ctx: &mut TxContext) {
        let registry = AccessRegistry {
            id: object::new(ctx),
            revoked_passes: table::new(ctx),
            active_passes: table::new(ctx),
        };
        transfer::share_object(registry);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // === Internal helpers ===
    fun has_active_pass(registry: &AccessRegistry, factory_id: ID, holder: address): bool {
        registry.active_passes.contains(ActivePassKey { factory_id, holder })
    }

    fun register_pass(registry: &mut AccessRegistry, factory_id: ID, holder: address, pass_id: ID) {
        registry.active_passes.add(ActivePassKey { factory_id, holder }, pass_id);
    }

    fun unregister_pass(registry: &mut AccessRegistry, factory_id: ID, holder: address) {
        if (registry.active_passes.contains(ActivePassKey { factory_id, holder })) {
            registry.active_passes.remove(ActivePassKey { factory_id, holder });
        };
    }

    // === Claim Functions ===

    public fun claim_from_blueprint(
        access_registry: &mut AccessRegistry,
        bpo: &BlueprintOriginal,
        line: &ProductionLine,
        ctx: &mut TxContext,
    ) {
        let factory_id = object::id(line);
        assert!(blueprint::bpo_recipe_id(bpo) == production_line::recipe_id_of(line), E_RECIPE_MISMATCH);
        assert!(!has_active_pass(access_registry, factory_id, ctx.sender()), E_DUPLICATE_PASS);

        let pass = AccessPass {
            id: object::new(ctx),
            factory_id,
            holder: ctx.sender(),
            pass_type: PASS_TYPE_BLUEPRINT,
            expires_at: option::none(),
        };
        let pass_id = object::id(&pass);
        register_pass(access_registry, factory_id, ctx.sender(), pass_id);
        event::emit(events::new_access_granted_event(
            pass_id, factory_id, ctx.sender(), PASS_TYPE_BLUEPRINT, option::none(),
        ));
        transfer::transfer(pass, ctx.sender());
    }

    /// Note: no Clock needed — lease::is_active already checks active state,
    /// and expiry is copied from lease for the pass's own expiry tracking.
    public fun claim_from_lease(
        access_registry: &mut AccessRegistry,
        lease: &LeaseAgreement,
        line: &ProductionLine,
        ctx: &mut TxContext,
    ) {
        let factory_id = object::id(line);
        assert!(lease::is_active(lease), E_LEASE_NOT_ACTIVE);
        assert!(lease::lessee(lease) == ctx.sender(), E_NOT_LESSEE);
        assert!(!has_active_pass(access_registry, factory_id, ctx.sender()), E_DUPLICATE_PASS);

        let expiry = lease::expiry(lease);
        let pass = AccessPass {
            id: object::new(ctx),
            factory_id,
            holder: ctx.sender(),
            pass_type: PASS_TYPE_LEASE,
            expires_at: option::some(expiry),
        };
        let pass_id = object::id(&pass);
        register_pass(access_registry, factory_id, ctx.sender(), pass_id);
        event::emit(events::new_access_granted_event(
            pass_id, factory_id, ctx.sender(), PASS_TYPE_LEASE, option::some(expiry),
        ));
        transfer::transfer(pass, ctx.sender());
    }

    public fun claim_from_work_order(
        access_registry: &mut AccessRegistry,
        wo: &WorkOrder,
        line: &ProductionLine,
        ctx: &mut TxContext,
    ) {
        let factory_id = object::id(line);
        let acceptor_opt = work_order::order_acceptor(wo);
        assert!(acceptor_opt.is_some() && *acceptor_opt.borrow() == ctx.sender(), E_NOT_ACCEPTOR);
        let status = work_order::order_status(wo);
        assert!(
            status == work_order::status_accepted() || status == work_order::status_delivering(),
            E_WO_NOT_ACTIVE,
        );
        assert!(!has_active_pass(access_registry, factory_id, ctx.sender()), E_DUPLICATE_PASS);

        let pass = AccessPass {
            id: object::new(ctx),
            factory_id,
            holder: ctx.sender(),
            pass_type: PASS_TYPE_WORK_ORDER,
            expires_at: option::none(),
        };
        let pass_id = object::id(&pass);
        register_pass(access_registry, factory_id, ctx.sender(), pass_id);
        event::emit(events::new_access_granted_event(
            pass_id, factory_id, ctx.sender(), PASS_TYPE_WORK_ORDER, option::none(),
        ));
        transfer::transfer(pass, ctx.sender());
    }

    // === Revocation ===

    public fun surrender_pass(
        access_registry: &mut AccessRegistry,
        pass: AccessPass,
        ctx: &TxContext,
    ) {
        assert!(pass.holder == ctx.sender(), E_NOT_PASS_HOLDER);
        let factory_id = pass.factory_id;
        let holder = pass.holder;
        let pass_id = object::id(&pass);
        unregister_pass(access_registry, factory_id, holder);
        event::emit(events::new_access_revoked_event(
            pass_id, factory_id, holder, string::utf8(b"surrender"),
        ));
        let AccessPass { id, factory_id: _, holder: _, pass_type: _, expires_at: _ } = pass;
        object::delete(id);
    }

    public fun revoke_expired(
        access_registry: &mut AccessRegistry,
        pass: AccessPass,
        clock: &Clock,
    ) {
        assert!(pass.expires_at.is_some(), E_PASS_NOT_EXPIRABLE);
        assert!(clock::timestamp_ms(clock) > *pass.expires_at.borrow(), E_NOT_YET_EXPIRED);
        let factory_id = pass.factory_id;
        let holder = pass.holder;
        let pass_id = object::id(&pass);
        unregister_pass(access_registry, factory_id, holder);
        event::emit(events::new_access_revoked_event(
            pass_id, factory_id, holder, string::utf8(b"expired"),
        ));
        let AccessPass { id, factory_id: _, holder: _, pass_type: _, expires_at: _ } = pass;
        object::delete(id);
    }

    public fun admin_revoke_pass(
        access_registry: &mut AccessRegistry,
        pass_id: ID,
        line: &ProductionLine,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == production_line::owner(line), E_NOT_AUTHORIZED);
        access_registry.revoked_passes.add(pass_id, true);
        event::emit(events::new_access_revoked_event(
            pass_id, object::id(line), ctx.sender(), string::utf8(b"admin_revoke"),
        ));
    }

    // === Query ===

    public fun is_pass_revoked(registry: &AccessRegistry, pass_id: ID): bool {
        registry.revoked_passes.contains(pass_id)
    }

    // === Gate Permit (placeholder — requires world::gate types) ===
    // public fun verify_and_issue_permit(
    //     access_registry: &AccessRegistry,
    //     source_gate: &Gate,
    //     dest_gate: &Gate,
    //     character: &Character,
    //     pass: &AccessPass,
    //     clock: &Clock,
    //     ctx: &mut TxContext,
    // ): ID { ... }

    // === Accessors ===
    public fun pass_factory_id(pass: &AccessPass): ID { pass.factory_id }
    public fun pass_holder(pass: &AccessPass): address { pass.holder }
    public fun pass_type(pass: &AccessPass): u8 { pass.pass_type }
    public fun pass_expires_at(pass: &AccessPass): Option<u64> { pass.expires_at }
}
```

- [ ] **Step 3: Build check**

Run: `cd packages/eve_integration && sui move build 2>&1 | tail -20`

Expected: Build succeeds.

- [ ] **Step 4: Run tests**

Run: `cd packages/eve_integration && sui move test 2>&1 | tail -20`

Expected: All access_tests + bridge_tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/eve_integration/sources/factory_access.move packages/eve_integration/tests/access_tests.move
git commit -m "feat(eve_integration): AccessPass lifecycle with registry-based revocation"
```

---

## Task 4: Monkey tests

**Files:**
- Create: `packages/eve_integration/tests/monkey_tests.move`

- [ ] **Step 1: Write extreme edge case tests**

Cover at minimum:
- `test_claim_and_immediate_surrender` — claim + surrender in same tx block
- `test_revoke_nonexistent_pass` — admin_revoke with random ID (should succeed silently or error)
- `test_add_duplicate_mapping` — same eve_type_id twice (should fail E_MAPPING_ALREADY_EXISTS)
- `test_enable_mapping_that_was_never_disabled` — should fail
- `test_remove_mapping_then_factory_override_stale` — remove global mapping, factory override references stale type
- `test_max_mappings_stress` — add 100+ mappings, verify lookup performance
- `test_factory_owner_cannot_create_new_mapping` — only disable existing ones

- [ ] **Step 2: Run all tests**

Run: `cd packages/eve_integration && sui move test 2>&1 | tail -30`

Expected: All tests pass (bridge + access + monkey).

- [ ] **Step 3: Commit**

```bash
git add packages/eve_integration/tests/monkey_tests.move
git commit -m "test(eve_integration): monkey tests for registry and access edge cases"
```

---

## Task 5: Frontend — PTB builders + types + error codes

**Files:**
- Create: `frontend/src/lib/ptb/eveBridge.ts`
- Create: `frontend/src/lib/ptb/factoryAccess.ts`
- Modify: `frontend/src/lib/types.ts`
- Modify: `frontend/src/lib/errors.ts`
- Modify: `frontend/.env`

- [ ] **Step 1: Add EVE integration types to types.ts**

Add after existing type definitions:

```typescript
// === EVE Integration Types ===
export interface ItemMapping {
  eveTypeId: string; // u64 as string
  materialId: string;
}

export interface FactoryOverride {
  factoryId: string;
  disabledTypes: string[]; // eve_type_ids
}

export interface AccessPassData {
  id: string;
  factoryId: string;
  holder: string;
  passType: number; // 0=blueprint, 1=lease, 2=work_order
  expiresAt: string | null; // epoch ms or null
}

export const PASS_TYPE = {
  BLUEPRINT: 0,
  LEASE: 1,
  WORK_ORDER: 2,
} as const;

export const PASS_TYPE_LABEL: Record<number, string> = {
  0: "Blueprint Holder",
  1: "Lessee",
  2: "Work Order",
};
```

- [ ] **Step 2: Add error codes to errors.ts**

Add to the `ERROR_MAP` object:

```typescript
// EVE Bridge errors (1001-1007)
1001: "Not authorized — only factory owner can perform this action",
1002: "SSU is offline — cannot perform inventory operations",
1003: "Item mapping not found in registry",
1004: "EVE type ID does not exist in global registry",
1005: "Quantity overflow — value exceeds u32 max",
1006: "Item mapping is disabled for this factory",
1007: "Mapping already exists in global registry",

// Factory Access errors (2001-2013)
2001: "Recipe mismatch — BPO recipe does not match factory",
2002: "Lease is not active",
2003: "You are not the lessee",
2004: "Work order is not in active state",
2005: "You are not the work order acceptor",
2006: "You are not the pass holder",
2007: "Access pass has expired",
2008: "Pass has not yet expired — cannot revoke",
2009: "Factory mismatch",
2010: "Pass does not have an expiry — cannot expire-revoke",
2011: "You already have an active pass for this factory",
2012: "Access pass has been revoked by admin",
2013: "Not authorized — only factory owner",
```

- [ ] **Step 3: Add .env variables**

Add to `frontend/.env`:

```
VITE_PKG_EVE_INTEGRATION=0x_PLACEHOLDER_EVE_INTEGRATION
VITE_GLOBAL_REGISTRY=0x_PLACEHOLDER_GLOBAL_REGISTRY
VITE_ACCESS_REGISTRY=0x_PLACEHOLDER_ACCESS_REGISTRY
```

- [ ] **Step 4: Create eveBridge.ts PTB builders**

```typescript
import { Transaction } from "@mysten/sui/transactions";

const PKG = () => import.meta.env.VITE_PKG_EVE_INTEGRATION;
const REGISTRY = () => import.meta.env.VITE_GLOBAL_REGISTRY;

export function buildAddGlobalMapping(
  adminCapId: string,
  eveTypeId: string,
  materialId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::eve_bridge::add_global_mapping`,
    arguments: [
      tx.object(REGISTRY()),
      tx.object(adminCapId),
      tx.pure.u64(eveTypeId),
      tx.pure.string(materialId),
    ],
  });
  return tx;
}

export function buildRemoveGlobalMapping(
  adminCapId: string,
  eveTypeId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::eve_bridge::remove_global_mapping`,
    arguments: [
      tx.object(REGISTRY()),
      tx.object(adminCapId),
      tx.pure.u64(eveTypeId),
    ],
  });
  return tx;
}

export function buildDisableFactoryMapping(
  lineId: string,
  eveTypeId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::eve_bridge::disable_factory_mapping`,
    arguments: [
      tx.object(REGISTRY()),
      tx.object(lineId),
      tx.pure.u64(eveTypeId),
    ],
  });
  return tx;
}

export function buildEnableFactoryMapping(
  lineId: string,
  eveTypeId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::eve_bridge::enable_factory_mapping`,
    arguments: [
      tx.object(REGISTRY()),
      tx.object(lineId),
      tx.pure.u64(eveTypeId),
    ],
  });
  return tx;
}

// SSU registration — uncomment when world types available
// export function buildRegisterOnSSU(ssuId: string, ownerCapId: string): Transaction { ... }
// export function buildRegisterOnGate(gateId: string, ownerCapId: string): Transaction { ... }
// export function buildProduceFromSSU(params: { ... }): Transaction { ... }
// export function buildCollectToSSU(params: { ... }): Transaction { ... }
```

- [ ] **Step 5: Create factoryAccess.ts PTB builders**

```typescript
import { Transaction } from "@mysten/sui/transactions";

const PKG = () => import.meta.env.VITE_PKG_EVE_INTEGRATION;
const ACCESS_REGISTRY = () => import.meta.env.VITE_ACCESS_REGISTRY;

export function buildClaimFromBlueprint(
  bpoId: string,
  lineId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::factory_access::claim_from_blueprint`,
    arguments: [
      tx.object(ACCESS_REGISTRY()),
      tx.object(bpoId),
      tx.object(lineId),
    ],
  });
  return tx;
}

export function buildClaimFromLease(
  leaseId: string,
  lineId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::factory_access::claim_from_lease`,
    arguments: [
      tx.object(ACCESS_REGISTRY()),
      tx.object(leaseId),
      tx.object(lineId),
    ],
  });
  return tx;
}

export function buildClaimFromWorkOrder(
  woId: string,
  lineId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::factory_access::claim_from_work_order`,
    arguments: [
      tx.object(ACCESS_REGISTRY()),
      tx.object(woId),
      tx.object(lineId),
    ],
  });
  return tx;
}

export function buildSurrenderPass(passId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::factory_access::surrender_pass`,
    arguments: [
      tx.object(ACCESS_REGISTRY()),
      tx.object(passId),
    ],
  });
  return tx;
}

export function buildRevokeExpired(passId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::factory_access::revoke_expired`,
    arguments: [
      tx.object(ACCESS_REGISTRY()),
      tx.object(passId),
      tx.object("0x6"), // Clock
    ],
  });
  return tx;
}

export function buildAdminRevokePass(
  passId: string,
  lineId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG()}::factory_access::admin_revoke_pass`,
    arguments: [
      tx.object(ACCESS_REGISTRY()),
      tx.pure.id(passId),
      tx.object(lineId),
    ],
  });
  return tx;
}
```

- [ ] **Step 6: Type check**

Run: `cd frontend && npx tsc --noEmit 2>&1 | tail -20`

Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/lib/ptb/eveBridge.ts frontend/src/lib/ptb/factoryAccess.ts frontend/src/lib/types.ts frontend/src/lib/errors.ts frontend/.env
git commit -m "feat(frontend): EVE integration PTB builders, types, and error codes"
```

---

## Task 6: Frontend — 4 new panes

**Files:**
- Create: `frontend/src/panes/SSUInventory.tsx` + `.module.css`
- Create: `frontend/src/panes/GateAccess.tsx` + `.module.css`
- Create: `frontend/src/panes/ItemMapping.tsx` + `.module.css`
- Create: `frontend/src/panes/LinkAssembly.tsx` + `.module.css`
- Modify: `frontend/src/config/paneRegistry.ts`

Each pane follows the existing pattern (see any existing pane like `LeaseManager.tsx` for reference):
- Wrapped in `<PaneChrome>` with title
- Uses `useSignAndExecuteTransaction` for mutations
- Uses `useToast` for success/error feedback
- CSS module with `.pane` root class using HUD theme variables

- [ ] **Step 1: Create SSUInventory pane**

Displays: connected SSU's open inventory items with EVE type_id + mapped Industrial material_id. Read-only view for now (SSU operations depend on world types).

- [ ] **Step 2: Create GateAccess pane**

Displays: all AccessPasses for this factory (query `getOwnedObjects` of type `AccessPass`). Actions: claim (from BPO/lease/WO), surrender, admin revoke.

- [ ] **Step 3: Create ItemMapping pane**

Displays: GlobalRegistry mappings. Actions: add/remove global (admin only), disable/enable factory override.

- [ ] **Step 4: Create LinkAssembly pane**

Displays: extension status for SSU/Gate. Actions: register extension (placeholder until world types). Info text about `freeze_extension_config`.

- [ ] **Step 5: Register panes in paneRegistry.ts**

Add 4 entries to the pane registry following the existing pattern.

- [ ] **Step 6: Type check + build**

Run: `cd frontend && npx tsc --noEmit && npm run build 2>&1 | tail -10`

Expected: Clean typecheck, production build passes.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/panes/SSU*.tsx frontend/src/panes/SSU*.css frontend/src/panes/Gate*.tsx frontend/src/panes/Gate*.css frontend/src/panes/Item*.tsx frontend/src/panes/Item*.css frontend/src/panes/Link*.tsx frontend/src/panes/Link*.css frontend/src/config/paneRegistry.ts
git commit -m "feat(frontend): 4 EVE integration panes (SSU, Gate, Mapping, Assembly)"
```

---

## Task 7: Watcher — 5 new rule handlers

**Files:**
- Create: `watcher/src/rules/auto-produce-from-ssu.ts`
- Create: `watcher/src/rules/auto-collect-to-ssu.ts`
- Create: `watcher/src/rules/auto-grant-access.ts`
- Create: `watcher/src/rules/auto-revoke-access.ts`
- Create: `watcher/src/rules/sync-registry.ts`
- Modify: `watcher/src/index.ts`
- Modify: `watcher/src/types.ts`
- Modify: `watcher/config.example.yaml`

Each rule handler implements the `RuleHandler` interface from `watcher/src/rules/interface.ts`:
```typescript
interface RuleHandler {
  readonly name: string;
  readonly description: string;
  readonly eventType?: string;
  readonly scheduleType?: "inventory" | "deadline" | "fleet";
  enabled: boolean;
  evaluate(signal: WatcherSignal, config: RuleConfig, now?: number): Promise<boolean>;
  buildTx(signal: WatcherSignal, config: RuleConfig): Promise<Transaction>;
}
```

- [ ] **Step 1: Add EVE types to watcher/src/types.ts**

```typescript
export interface EveIntegrationConfig {
  eve_pkg_id: string;
  global_registry_id: string;
  access_registry_id: string;
  ssu_id?: string;         // linked SSU (optional until world integration)
  gate_source_id?: string;
  gate_dest_id?: string;
}
```

- [ ] **Step 2: Create auto-produce-from-ssu.ts**

Trigger: SSU inventory change. Condition: recipe inputs satisfied. Action: `produce_from_ssu` PTB. Follow pattern of existing `auto-restock.ts`.

- [ ] **Step 3: Create auto-collect-to-ssu.ts**

Trigger: `ProductionCompletedEvent`. Action: `collect_to_ssu` PTB. Follow pattern of `production-completer.ts`.

- [ ] **Step 4: Create auto-grant-access.ts**

Trigger: `BlueprintMintedEvent` / `LeaseCreatedEvent` / `WorkOrderAcceptedEvent`. Action: claim AccessPass. Note limitation: watcher can only claim for its own address.

- [ ] **Step 5: Create auto-revoke-access.ts**

Trigger: Clock poll for expired passes. Action: `revoke_expired` PTB (permissionless).

- [ ] **Step 6: Create sync-registry.ts**

Trigger: `GlobalMappingAddedEvent` / `GlobalMappingRemovedEvent`. Action: log notification, check for stale factory overrides.

- [ ] **Step 7: Register handlers in index.ts**

Add to the rule registration block in `watcher/src/index.ts`:

```typescript
import { AutoProduceFromSSU } from "./rules/auto-produce-from-ssu";
import { AutoCollectToSSU } from "./rules/auto-collect-to-ssu";
import { AutoGrantAccess } from "./rules/auto-grant-access";
import { AutoRevokeAccess } from "./rules/auto-revoke-access";
import { SyncRegistry } from "./rules/sync-registry";

// In the registration block:
registry.register(new AutoProduceFromSSU());
registry.register(new AutoCollectToSSU());
registry.register(new AutoGrantAccess());
registry.register(new AutoRevokeAccess());
registry.register(new SyncRegistry());
```

- [ ] **Step 8: Update config.example.yaml**

Add `eve_integration` section:

```yaml
eve_integration:
  enabled: true
  eve_pkg_id: "0x_EVE_INTEGRATION_PKG"
  global_registry_id: "0x_GLOBAL_REGISTRY"
  access_registry_id: "0x_ACCESS_REGISTRY"
  # ssu_id: "0x_SSU"           # Uncomment when linked to EVE SSU
  # gate_source_id: "0x_GATE1"
  # gate_dest_id: "0x_GATE2"
```

- [ ] **Step 9: Run watcher tests + typecheck**

Run: `cd watcher && npx tsc --noEmit && npm test 2>&1 | tail -20`

Expected: Typecheck clean, existing 73 tests pass, new rule handler tests pass.

- [ ] **Step 10: Commit**

```bash
git add watcher/src/rules/auto-*.ts watcher/src/rules/sync-registry.ts watcher/src/index.ts watcher/src/types.ts watcher/config.example.yaml
git commit -m "feat(watcher): 5 EVE integration rule handlers"
```

---

## Task 8: Deploy + Frontend publish

**Files:**
- Modify: `frontend/.env` (update with deployed package IDs)

- [ ] **Step 1: Deploy eve_integration to testnet**

Run: `cd packages/eve_integration && sui client publish --gas-budget 500000000 2>&1`

Record: package ID, GlobalRegistry ID, AccessRegistry ID.

If world dependency causes publish failure, temporarily remove world import and deploy registry-only version first.

- [ ] **Step 2: Update .env with real IDs**

Update `VITE_PKG_EVE_INTEGRATION`, `VITE_GLOBAL_REGISTRY`, `VITE_ACCESS_REGISTRY`.

- [ ] **Step 3: Seed GlobalRegistry with initial mappings**

Use `sui client call` or a script to add initial EVE type_id → material_id mappings:

```bash
sui client call --package $PKG --module eve_bridge --function add_global_mapping \
  --args $REGISTRY $ADMIN_CAP 12001 "tritanium" --gas-budget 10000000
```

- [ ] **Step 4: Build and deploy frontend**

```bash
cd frontend && npm run build
npx vercel --prod  # or other deployment platform
```

Record the public URL.

- [ ] **Step 5: Commit deployment records**

```bash
git add frontend/.env
git commit -m "deploy: eve_integration testnet + frontend URL"
```

---

## Task 9: Update progress + notes

**Files:**
- Modify: `tasks/progress.md`

- [ ] **Step 1: Update progress.md**

Add completed tasks, test counts, deployment info.

- [ ] **Step 2: Update move-notes.md (if exists) or tasks/notes.md**

Document: EVE world dependency status, function name mappings, AccessRegistry pattern decision, known limitations.

---

## Dependency Graph

```
Task 1 (scaffold) → Task 2 (eve_bridge) → Task 3 (factory_access) → Task 4 (monkey tests)
                                                                          ↓
Task 5 (frontend PTB/types) ←────────────────────────────────────────────┘
         ↓
Task 6 (frontend panes)
         ↓
Task 7 (watcher rules) ← can run in parallel with Task 6
         ↓
Task 8 (deploy) ← depends on Tasks 4, 6, 7
         ↓
Task 9 (progress)
```

**Parallelizable:** Tasks 6 and 7 can run concurrently after Task 5.

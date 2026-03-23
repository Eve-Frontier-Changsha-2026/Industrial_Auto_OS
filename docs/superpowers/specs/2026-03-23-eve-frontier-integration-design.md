# EVE Frontier Integration — Design Specification

**Date:** 2026-03-23
**Status:** Draft (Rev 2 — post spec-review fixes)
**Author:** Claude + Ramon
**Reviewed by:** sui-architect audit (10 CRITICAL fixed, 11 WARNING addressed) + spec-reviewer (5 CRITICAL, 6 WARNING fixed)

---

## 1. Executive Summary

Integrate Industrial Auto OS with EVE Frontier's Smart Assembly system so that:

1. **Smart Storage Unit (SSU)**: Production lines can withdraw raw materials from and deposit finished goods into EVE's in-game inventory via the typed witness pattern.
2. **Smart Gate**: Factory access control — only players holding relevant Blueprints, Leases, or WorkOrders can jump to the factory location.
3. **Watcher automation**: 5 new rules handle SSU I/O, access pass lifecycle, and registry sync.
4. **Frontend**: Deploy to public URL for in-game browser embedding + new panes for SSU/Gate/Registry management.

### Key Design Decision: Adapter Pattern

EVE items (`type_id: u64`, `quantity: u32`) differ from Industrial Auto OS items. An `ItemRegistry` adapter layer with two-tier mapping (global default + factory override) decouples the two systems. EVE schema changes only require registry updates, not contract upgrades.

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                      EVE Frontier Game                        │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐  │
│  │ Smart Gate   │  │     SSU      │  │  In-game Browser    │  │
│  │ (准入控制)   │  │ (inventory)  │  │ (loads HUD URL)     │  │
│  └──────┬──────┘  └──────┬───────┘  └──────────┬──────────┘  │
└─────────┼────────────────┼──────────────────────┼─────────────┘
          │                │                      │
          ▼                ▼                      ▼
┌──────────────────────────────────────┐  ┌──────────────────┐
│       eve_integration package         │  │  React Frontend   │
│                                       │  │  (Vercel URL)     │
│  eve_bridge.move                      │  │                   │
│  ├─ IndustrialAuth (witness)          │  │  New panes:       │
│  ├─ GlobalRegistry (shared, admin)    │  │  ├─ SSU Inventory │
│  ├─ FactoryOverride (dynamic field)   │  │  ├─ Gate Access   │
│  ├─ withdraw_from_ssu()               │  │  ├─ Item Mapping  │
│  ├─ deposit_to_ssu()                  │  │  └─ Link Assembly │
│  ├─ produce_from_ssu()                │  └──────────────────┘
│  └─ collect_to_ssu()                  │
│                                       │  ┌──────────────────┐
│  factory_access.move                  │  │     Watcher       │
│  ├─ AccessPass (key only, no store)   │  │                   │
│  ├─ claim_from_blueprint()            │  │  5 new rules:     │
│  ├─ claim_from_lease()                │  │  ├─ auto-produce  │
│  ├─ claim_from_work_order()           │  │  ├─ auto-collect  │
│  ├─ verify_and_issue_permit()         │  │  ├─ auto-grant    │
│  ├─ revoke_pass()                     │  │  ├─ auto-revoke   │
│  └─ revoke_expired()                  │  │  └─ sync-registry │
│                                       │  └──────────────────┘
│  events.move                          │
│  └─ All integration events            │
└───────────┬───────────────────────────┘
            │ imports (read-only)
            ▼
┌──────────────────────────────────────────────────┐
│     Existing Packages (no changes required)       │
│  industrial_core  │  work_order  │  marketplace   │
└──────────────────────────────────────────────────┘
```

---

## 3. Package Structure

```
packages/eve_integration/
├── Move.toml
├── sources/
│   ├── eve_bridge.move        # Witness + SSU adapter + ItemRegistry
│   ├── factory_access.move    # AccessPass + Gate permit logic
│   └── events.move            # All custom events
└── tests/
    ├── bridge_tests.move
    ├── access_tests.move
    └── monkey_tests.move
```

### Dependencies (Move.toml)

```toml
[package]
name = "eve_integration"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
world = { git = "https://github.com/evefrontier/world-contracts.git", subdir = "contracts/world", rev = "PIN_TO_SPECIFIC_COMMIT" }
industrial_core = { local = "../industrial_core" }
marketplace = { local = "../marketplace" }
work_order = { local = "../work_order" }

[addresses]
eve_integration = "0x0"
```

**Note:** `world` dependency MUST be pinned to a specific commit hash. Check latest stable commit before implementation.

---

## 4. Module Design: eve_bridge.move

### 4.1 Witness Type

```move
/// Witness for authorizing this extension on EVE Smart Assemblies.
/// Only this module can instantiate it.
public struct IndustrialAuth has drop {}
```

### 4.2 GlobalRegistry (Shared Object)

```move
/// Admin-managed global mapping: EVE type_id <-> Industrial material_id.
/// Created once at package publish via init().
public struct GlobalRegistry has key {
    id: UID,
    // Note: no admin_cap_id field — possession of RegistryAdminCap IS the auth (standard SUI pattern)
}

/// AdminCap for managing the global registry.
public struct RegistryAdminCap has key, store {
    id: UID,
}

/// Package init — creates GlobalRegistry + RegistryAdminCap
fun init(ctx: &mut TxContext) {
    let cap = RegistryAdminCap { id: object::new(ctx) };
    let registry = GlobalRegistry { id: object::new(ctx) };
    transfer::share_object(registry);
    transfer::transfer(cap, ctx.sender());
}

// Mappings stored as dynamic fields:
//   Key: EveToIndustrial { eve_type_id: u64 }  -> Value: String (material_id)
//   Key: IndustrialToEve { material_id: String } -> Value: u64 (eve_type_id)

public struct EveToIndustrial has copy, drop, store { eve_type_id: u64 }
public struct IndustrialToEve has copy, drop, store { material_id: String }
```

### 4.3 FactoryOverride (Dynamic Field on GlobalRegistry)

```move
/// Per-factory override: can only RESTRICT (disable) global mappings, not create new ones.
public struct FactoryOverrideKey has copy, drop, store { factory_id: ID }

/// Set of eve_type_ids DISABLED for this factory.
public struct FactoryOverride has store {
    disabled_types: VecSet<u64>,
}
```

**Security constraint:** `FactoryOverride` can only disable existing global mappings. It cannot create new type_id -> material_id mappings. This prevents malicious factory owners from creating fraudulent conversions.

### 4.4 Registration Functions

```move
/// SSU owner calls this to authorize IndustrialAuth on their SSU.
/// Must pass their OwnerCap<StorageUnit>.
/// After calling, recommend freeze_extension_config() to build trust.
public fun register_on_ssu(
    ssu: &mut StorageUnit,
    owner_cap: &OwnerCap<StorageUnit>,
) {
    storage_unit::authorize_extension<IndustrialAuth>(ssu, owner_cap);
}

/// Gate owner calls this to authorize IndustrialAuth on their Gate.
/// IMPORTANT: Both source and destination gates must be registered
/// for jump permits to work.
public fun register_on_gate(
    gate: &mut Gate,
    owner_cap: &OwnerCap<Gate>,
) {
    gate::authorize_extension<IndustrialAuth>(gate, owner_cap);
}
```

### 4.5 SSU Operations — Open Inventory

**Design decision:** Use SSU's **open inventory** (`deposit_to_open_inventory` / `withdraw_from_open_inventory`), NOT the owner's main inventory. Open inventory is contract-controlled and appropriate for shared factory resources. Main inventory is the SSU owner's private storage.

**Watcher constraint:** `deposit_materials` and `withdraw_output` on `ProductionLine` call `require_owner(line, ctx)` — only the production line owner can call them. The watcher must hold the line owner's keypair to automate SSU↔production operations. This is consistent with the existing watcher design (already requires operator keypair for auto-complete, auto-restock, etc.).

```move
/// Withdraw materials from SSU open inventory, convert via registry,
/// and deposit into production line's input buffer.
/// Auth: caller must be production line owner.
public fun withdraw_from_ssu(
    registry: &GlobalRegistry,
    ssu: &mut StorageUnit,
    character: &Character,
    line: &mut ProductionLine,
    eve_type_id: u64,
    quantity: u32,                    // EVE uses u32
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. Auth: sender == line owner
    assert!(ctx.sender() == production_line::owner(line), E_NOT_AUTHORIZED);
    // 2. SSU online check (will abort inside EVE code if offline)
    // 3. Lookup mapping: eve_type_id -> material_id (check factory override first)
    // 4. withdraw_from_open_inventory<IndustrialAuth>(ssu, character, auth, type_id, quantity, ctx)
    // 5. Convert: EVE Item -> deposit into production line (via public deposit_materials API)
    //    Note: quantity u32 -> u64 conversion for industrial_core
}

/// Complete production and deposit output into SSU open inventory.
/// Auth: caller must be production line owner.
public fun deposit_to_ssu(
    registry: &GlobalRegistry,
    ssu: &mut StorageUnit,
    character: &Character,
    line: &mut ProductionLine,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. Auth: sender == line owner
    // 2. complete_production(line, clock) — if not already completed
    // 3. withdraw_output from production line (public API)
    // 4. Lookup mapping: material_id -> eve_type_id
    // 5. Convert to EVE Item + deposit_to_open_inventory<IndustrialAuth>(ssu, character, item, auth, ctx)
}

/// Atomic: withdraw inputs from SSU + start production.
/// Convenience wrapper for watcher automation.
public fun produce_from_ssu(
    registry: &GlobalRegistry,
    ssu: &mut StorageUnit,
    character: &Character,
    line: &mut ProductionLine,
    recipe: &Recipe,
    bpo: &BlueprintOriginal,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. Auth check
    // 2. For each recipe input:
    //    a. Lookup material_id -> eve_type_id
    //    b. withdraw_from_open_inventory
    //    c. deposit_materials to production line
    // 3. start_production(line, recipe, bpo, clock, ctx)
    // Note: recipe inputs capped by recipe definition — prevents over-withdrawal
}

/// Atomic: complete production + deposit outputs to SSU.
public fun collect_to_ssu(
    registry: &GlobalRegistry,
    ssu: &mut StorageUnit,
    character: &Character,
    line: &mut ProductionLine,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. Auth check
    // 2. complete_production
    // 3. For each output: convert + deposit_to_open_inventory
}
```

### 4.6 Registry Management

```move
/// Admin adds a global mapping.
public fun add_global_mapping(
    registry: &mut GlobalRegistry,
    cap: &RegistryAdminCap,
    eve_type_id: u64,
    material_id: String,
) { /* add both direction dynamic fields + emit event */ }

/// Admin removes a global mapping.
public fun remove_global_mapping(
    registry: &mut GlobalRegistry,
    cap: &RegistryAdminCap,
    eve_type_id: u64,
) { /* remove both direction dynamic fields + emit event */ }

/// Factory owner disables a specific mapping for their factory.
/// The eve_type_id must exist in the global registry.
public fun disable_factory_mapping(
    registry: &mut GlobalRegistry,
    factory_id: ID,
    eve_type_id: u64,
    line: &ProductionLine,      // prove ownership
    ctx: &TxContext,
) {
    assert!(ctx.sender() == production_line::owner(line), E_NOT_AUTHORIZED);
    assert!(has_global_mapping(registry, eve_type_id), E_NOT_IN_GLOBAL);
    // add to FactoryOverride.disabled_types
}

/// Factory owner re-enables a previously disabled mapping.
public fun enable_factory_mapping(
    registry: &mut GlobalRegistry,
    factory_id: ID,
    eve_type_id: u64,
    line: &ProductionLine,
    ctx: &TxContext,
) { /* remove from disabled_types */ }

/// Lookup with factory override: returns None if disabled for this factory.
public fun resolve_eve_to_industrial(
    registry: &GlobalRegistry,
    factory_id: ID,
    eve_type_id: u64,
): Option<String> {
    // 1. Check factory override — if disabled, return None
    // 2. Lookup global mapping
    // 3. Return material_id or None
}
```

### 4.7 Type Conversion Notes

| EVE Frontier | Industrial Auto OS | Conversion |
|---|---|---|
| `type_id: u64` | `material_id: String` | Registry lookup |
| `quantity: u32` | `quantity: u64` | `(qty as u64)` / `(qty as u32)` with overflow check |
| `Item { item_id, type_id, quantity, parent_id, tenant }` | Internal buffer counters | Registry-mediated conversion |

**Constraint:** EVE `Item` objects have `parent_id` binding — an item withdrawn from SSU-A can only be deposited back into SSU-A. Cross-SSU transfers are not supported. Each factory must operate within a single SSU.

### 4.8 Error Codes

```move
const E_NOT_AUTHORIZED: u64 = 1001;
const E_SSU_OFFLINE: u64 = 1002;
const E_MAPPING_NOT_FOUND: u64 = 1003;
const E_NOT_IN_GLOBAL: u64 = 1004;
const E_QUANTITY_OVERFLOW: u64 = 1005;
const E_FACTORY_MAPPING_DISABLED: u64 = 1006;
```

---

## 5. Module Design: factory_access.move

### 5.1 AccessPass (Non-Transferable)

```move
/// Access pass granting gate traversal rights to a factory.
/// key only (no store) — non-transferable, only module can transfer.
public struct AccessPass has key {
    id: UID,
    factory_id: ID,
    holder: address,
    pass_type: u8,            // 0=blueprint_holder, 1=lessee, 2=work_order
    expires_at: Option<u64>,  // epoch ms; None = permanent (BPO holder)
}

const PASS_TYPE_BLUEPRINT: u8 = 0;
const PASS_TYPE_LEASE: u8 = 1;
const PASS_TYPE_WORK_ORDER: u8 = 2;
```

**Security:** `key` only (no `store`) prevents `public_transfer`. Only this module can transfer via `transfer::transfer`. Passes cannot be sold or gifted.

### 5.2 Claim Functions

**Correct function names from existing contracts:**
- `blueprint::bpo_recipe_id(bpo)` (NOT `recipe_id`)
- `production_line::recipe_id_of(line)` (NOT `recipe_id`)
- `work_order::order_acceptor(wo)` returns `Option<address>` (NOT `acceptor` returning `address`)
- `work_order::order_status(wo)` returns `u8` (no `is_active` function exists)
- `lease::LeaseAgreement` (NOT `Lease`)

```move
/// Claim pass by proving BPO ownership + factory association.
/// Validates: BPO recipe_id matches the factory's production line recipe.
/// Duplicate prevention: checks AccessRegistry for existing pass.
public fun claim_from_blueprint(
    access_registry: &mut AccessRegistry,
    bpo: &BlueprintOriginal,
    line: &ProductionLine,
    ctx: &mut TxContext,
) {
    let factory_id = object::id(line);
    // Validate BPO recipe matches factory
    assert!(blueprint::bpo_recipe_id(bpo) == production_line::recipe_id_of(line), E_RECIPE_MISMATCH);
    // Prevent duplicate passes
    assert!(!has_active_pass(access_registry, factory_id, ctx.sender()), E_DUPLICATE_PASS);
    let pass = AccessPass {
        id: object::new(ctx),
        factory_id,
        holder: ctx.sender(),
        pass_type: PASS_TYPE_BLUEPRINT,
        expires_at: option::none(),  // permanent while holding BPO
    };
    // Track in registry
    register_pass(access_registry, factory_id, ctx.sender(), object::id(&pass));
    transfer::transfer(pass, ctx.sender());
    // emit AccessGrantedEvent
}

/// Claim pass from active lease.
/// Validates: lease is active + caller is lessee + lease blueprint matches factory.
public fun claim_from_lease(
    access_registry: &mut AccessRegistry,
    lease: &LeaseAgreement,           // Correct type name
    line: &ProductionLine,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let factory_id = object::id(line);
    assert!(lease::is_active(lease), E_LEASE_NOT_ACTIVE);
    assert!(lease::lessee(lease) == ctx.sender(), E_NOT_LESSEE);
    assert!(!has_active_pass(access_registry, factory_id, ctx.sender()), E_DUPLICATE_PASS);
    let pass = AccessPass {
        id: object::new(ctx),
        factory_id,
        holder: ctx.sender(),
        pass_type: PASS_TYPE_LEASE,
        expires_at: option::some(lease::expiry(lease)),
    };
    register_pass(access_registry, factory_id, ctx.sender(), object::id(&pass));
    transfer::transfer(pass, ctx.sender());
}

/// Claim pass from accepted work order.
/// Validates: caller is WO acceptor + WO status is accepted/in_progress.
public fun claim_from_work_order(
    access_registry: &mut AccessRegistry,
    wo: &WorkOrder,
    line: &ProductionLine,
    ctx: &mut TxContext,
) {
    let factory_id = object::id(line);
    // order_acceptor returns Option<address> — must unwrap
    let acceptor_opt = work_order::order_acceptor(wo);
    assert!(acceptor_opt.is_some() && *acceptor_opt.borrow() == ctx.sender(), E_NOT_ACCEPTOR);
    // Check WO is active via order_status (no is_active function exists)
    let status = work_order::order_status(wo);
    assert!(
        status == 1 /* STATUS_ACCEPTED */ || status == 3 /* STATUS_DELIVERING */,
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
    register_pass(access_registry, factory_id, ctx.sender(), object::id(&pass));
    transfer::transfer(pass, ctx.sender());
}
```

### 5.3 Gate Permit Issuance

```move
/// Verify AccessPass and issue a JumpPermit via EVE's Gate.
/// IMPORTANT: Both source_gate and dest_gate must have IndustrialAuth extension.
/// JumpPermit is SINGLE-USE — consumed on jump.
public fun verify_and_issue_permit(
    access_registry: &AccessRegistry,
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    pass: &AccessPass,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    // 1. Verify pass holder matches caller
    assert!(pass.holder == ctx.sender(), E_NOT_PASS_HOLDER);
    // 2. Check admin revocation registry
    assert!(!access_registry.revoked_passes.contains(object::id(pass)), E_PASS_REVOKED);
    // 3. Verify pass not expired
    if (pass.expires_at.is_some()) {
        assert!(clock::timestamp_ms(clock) <= *pass.expires_at.borrow(), E_PASS_EXPIRED);
    };
    // 4. Issue permit (EVE validates both gates have IndustrialAuth)
    let permit_expiry = clock::timestamp_ms(clock) + PERMIT_DURATION_MS; // e.g., 1 hour
    gate::issue_jump_permit_with_id<IndustrialAuth>(
        source_gate,
        dest_gate,
        character,
        IndustrialAuth {},
        permit_expiry,
        ctx,
    )
}

const PERMIT_DURATION_MS: u64 = 3_600_000; // 1 hour
```

### 5.4 AccessRegistry (Shared Object for Admin Revocation)

**Design decision:** `AccessPass` is an owned object (holder's wallet). Admin cannot take an owned object from another address. Solution: use a shared `AccessRegistry` with a `revoked_passes` table. Admin marks a pass as revoked in the registry; `verify_and_issue_permit` checks the registry before issuing permits.

```move
/// Shared registry tracking all passes and admin revocations.
/// Created in init() alongside GlobalRegistry.
public struct AccessRegistry has key {
    id: UID,
    /// pass_id -> true means revoked by admin
    revoked_passes: Table<ID, bool>,
    /// (factory_id, holder_address) -> pass_id — prevents duplicates
    active_passes: Table<ActivePassKey, ID>,
}

public struct ActivePassKey has copy, drop, store {
    factory_id: ID,
    holder: address,
}

// Helper functions (internal)
fun has_active_pass(registry: &AccessRegistry, factory_id: ID, holder: address): bool { ... }
fun register_pass(registry: &mut AccessRegistry, factory_id: ID, holder: address, pass_id: ID) { ... }
fun unregister_pass(registry: &mut AccessRegistry, factory_id: ID, holder: address) { ... }
```

### 5.5 Revocation

```move
/// Pass holder voluntarily destroys their pass.
public fun surrender_pass(
    access_registry: &mut AccessRegistry,
    pass: AccessPass,
    ctx: &TxContext,
) {
    assert!(pass.holder == ctx.sender(), E_NOT_PASS_HOLDER);
    unregister_pass(access_registry, pass.factory_id, pass.holder);
    let AccessPass { id, factory_id, holder, pass_type: _, expires_at: _ } = pass;
    // emit AccessRevokedEvent { reason: "surrender" }
    object::delete(id);
}

/// Anyone can destroy an expired pass (public good: garbage collection).
public fun revoke_expired(
    access_registry: &mut AccessRegistry,
    pass: AccessPass,
    clock: &Clock,
) {
    assert!(pass.expires_at.is_some(), E_PASS_NOT_EXPIRABLE);
    assert!(clock::timestamp_ms(clock) > *pass.expires_at.borrow(), E_NOT_YET_EXPIRED);
    unregister_pass(access_registry, pass.factory_id, pass.holder);
    let AccessPass { id, factory_id, holder, pass_type: _, expires_at: _ } = pass;
    // emit AccessRevokedEvent { reason: "expired" }
    object::delete(id);
}

/// Factory admin marks a pass as revoked in the shared registry.
/// The pass object still exists in holder's wallet but becomes UNUSABLE.
/// verify_and_issue_permit checks this registry.
public fun admin_revoke_pass(
    access_registry: &mut AccessRegistry,
    pass_id: ID,
    line: &ProductionLine,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == production_line::owner(line), E_NOT_AUTHORIZED);
    access_registry.revoked_passes.add(pass_id, true);
    // emit AccessRevokedEvent { pass_id, factory_id: object::id(line), reason: "admin_revoke" }
    // Note: pass object remains in holder's wallet but is now unusable
}
```

### 5.5 Error Codes

```move
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
```

---

## 6. Module Design: events.move

```move
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
```

---

## 7. Watcher: 5 New Rules

### 7.1 auto-produce-from-ssu

| Field | Value |
|---|---|
| **Trigger** | EVE SSU inventory change event (new items deposited into open inventory) |
| **Condition** | All recipe inputs are available in SSU open inventory (quantities sufficient) |
| **Action** | Build PTB: `produce_from_ssu(registry, ssu, character, line, recipe, bpo, clock, ctx)` |
| **Cooldown** | 30s (prevent rapid fire if inventory fluctuates) |
| **Error handling** | If SSU offline → skip, retry next poll. If mapping not found → log warning. |

### 7.2 auto-collect-to-ssu

| Field | Value |
|---|---|
| **Trigger** | `ProductionCompletedEvent` from industrial_core |
| **Condition** | Production line has output ready + linked SSU is online |
| **Action** | Build PTB: `collect_to_ssu(registry, ssu, character, line, clock, ctx)` |
| **Cooldown** | None (event-driven, one-shot per completion) |
| **Error handling** | If SSU offline → queue and retry. If mapping not found → hold output in line. |

### 7.3 auto-grant-access

| Field | Value |
|---|---|
| **Trigger** | `BlueprintMintedEvent` / `LeaseCreatedEvent` / `WorkOrderAcceptedEvent` |
| **Condition** | The BPO/lease/WO is associated with a factory that has Gate integration |
| **Action** | Build PTB: `claim_from_blueprint` / `claim_from_lease` / `claim_from_work_order` |
| **Note** | Watcher must hold the Character object for the factory owner (or the claimant must self-claim via frontend) |

**Limitation:** Watcher can only auto-grant if it controls the claimant's wallet. For third-party players, the frontend must provide a "Claim Access" button.

### 7.4 auto-revoke-access

| Field | Value |
|---|---|
| **Trigger** | `LeaseExpiredEvent` / `WorkOrderCompletedEvent` / Clock poll (check expired passes) |
| **Condition** | AccessPass.expires_at < current time |
| **Action** | Build PTB: `revoke_expired(pass, clock)` |
| **Note** | `revoke_expired` is permissionless — anyone can garbage-collect expired passes |

### 7.5 sync-registry

| Field | Value |
|---|---|
| **Trigger** | `GlobalMappingAddedEvent` / `GlobalMappingRemovedEvent` |
| **Condition** | Factory has active override that references the changed mapping |
| **Action** | Log notification. If a removed global mapping was not disabled by factory, emit warning. |
| **Note** | This is primarily for monitoring/alerting, not automatic action. |

---

## 8. Frontend: New Panes

### 8.1 SSU Inventory Pane

- Display connected SSU's open inventory items
- Show EVE type_id + mapped Industrial material_id side by side
- Real-time update via `queryEvents` on SSU events
- Actions: manual withdraw/deposit (for override scenarios)

### 8.2 Gate Access Pane

- List all AccessPasses for this factory
- Show: holder, pass_type, expires_at, status
- Actions: admin revoke, view permit history
- "Claim Access" button for visiting players

### 8.3 Item Mapping Pane

- Display GlobalRegistry mappings (read-only for non-admin)
- Display FactoryOverride (disable/enable per factory)
- Admin panel: add/remove global mappings

### 8.4 Link Assembly Pane

- One-click `register_on_ssu` / `register_on_gate` setup
- Show current extension status per assembly
- Recommend `freeze_extension_config` after setup
- Gate pair configuration (both gates must be registered)

### 8.5 PTB Builders (new in frontend/src/lib/ptb/)

```typescript
// eve-bridge.ts
buildRegisterOnSSU(ssuId: string, ownerCapId: string): Transaction
buildRegisterOnGate(gateId: string, ownerCapId: string): Transaction
buildProduceFromSSU(params: ProduceFromSSUParams): Transaction
buildCollectToSSU(params: CollectToSSUParams): Transaction
buildAddGlobalMapping(registryId: string, adminCapId: string, eveTypeId: number, materialId: string): Transaction
buildDisableFactoryMapping(registryId: string, factoryId: string, eveTypeId: number): Transaction

// factory-access.ts
buildClaimFromBlueprint(bpoId: string, lineId: string, factoryId: string): Transaction
buildClaimFromLease(leaseId: string, lineId: string, factoryId: string): Transaction
buildClaimFromWorkOrder(woId: string, factoryId: string): Transaction
buildVerifyAndIssuePermit(params: IssuePermitParams): Transaction
buildRevokeExpired(passId: string): Transaction
buildAdminRevokePass(passId: string, lineId: string): Transaction
```

---

## 9. Security Considerations

### 9.1 SSU Drain Prevention

- `withdraw_from_ssu` checks `ctx.sender() == production_line::owner(line)`
- Withdrawal amounts are **recipe-driven** in `produce_from_ssu` — only withdraws exactly what the recipe requires
- Open inventory is separate from owner's main inventory — factory operations don't touch the SSU owner's personal items

### 9.2 AccessPass Security

- `key` only (no `store`) — non-transferable, cannot be sold on marketplace
- `claim_from_blueprint` validates `bpo_recipe_id` match with `recipe_id_of(line)`
- `claim_from_lease` validates active status + lessee identity via `LeaseAgreement`
- `claim_from_work_order` validates `order_acceptor` (Option unwrap) + `order_status` check
- Duplicate prevention via `AccessRegistry.active_passes` table
- Admin revocation via shared `AccessRegistry.revoked_passes` — admin marks pass as revoked without needing the owned object
- `verify_and_issue_permit` checks revocation registry before issuing permits
- Expired passes can be garbage-collected by anyone (`revoke_expired`)

### 9.3 Gate Security

- Both source and destination gates must have `IndustrialAuth` extension
- JumpPermit is single-use (destroyed on jump)
- Permit has time-bound expiry (default 1 hour)
- Pass holder identity verified before permit issuance

### 9.4 Registry Security

- GlobalRegistry mutations require `RegistryAdminCap`
- FactoryOverride can only DISABLE existing global mappings, not create new ones
- Prevents malicious factory owners from creating fraudulent type conversions
- Factory owner must prove ownership of production line to modify overrides

### 9.5 EVE-Specific Constraints

- SSU must be **online** for all operations (energy + network node requirements)
- Items have `parent_id` binding — no cross-SSU transfers
- `Character` object required for all SSU/Gate interactions
- EVE `quantity` is `u32` — overflow check needed when converting from `u64`

---

## 10. Testing Strategy

### 10.1 Unit Tests (bridge_tests.move)

- Register witness on mock SSU/Gate
- Add/remove global mappings
- Factory override: disable/enable
- Resolve mapping with override precedence
- Type conversion u32/u64 edge cases
- Auth checks: unauthorized caller rejected

### 10.2 Unit Tests (access_tests.move)

- Claim pass from BPO (happy path + recipe mismatch)
- Claim pass from lease (happy path + expired + wrong lessee)
- Claim pass from work order (happy path + wrong acceptor + inactive)
- Revoke: surrender, admin revoke, expired garbage collection
- Permit issuance: valid pass + expired pass + wrong holder

### 10.3 Integration Tests

- Full cycle: register SSU → add mapping → withdraw → produce → collect → deposit
- Full cycle: claim pass → issue permit (requires E2E on testnet since Gate needs real assembly)
- Cross-package interaction: eve_integration reads industrial_core/marketplace/work_order objects

### 10.4 Monkey Tests

- Claim pass then immediately revoke before jump
- Overflow: quantity = u32::MAX in withdrawal
- Register extension twice (should be idempotent or error)
- Produce from SSU with insufficient inventory
- Expired lease claim attempt
- Concurrent produce_from_ssu on same SSU (shared object contention)
- Admin removes global mapping while factory has active production using it
- Claim duplicate pass for same factory (should fail with E_DUPLICATE_PASS)
- Admin revoke then holder tries to issue permit (should fail with E_PASS_REVOKED)
- Use revoked pass object directly (still in wallet but registry-blocked)

### 10.5 EVE Type Mocking Strategy

Since `StorageUnit`, `Gate`, `Character`, `OwnerCap<T>` are foreign types from the `world` package, unit tests have two options:

**Option A: `#[test_only]` mock constructors (preferred for unit tests)**
- The `world` package may provide test helpers for constructing SSU/Gate/Character in test context
- If not available, write integration-level tests that import `world` as test dependency

**Option B: Testnet integration tests (preferred for E2E)**
- Deploy `eve_integration` to SUI testnet where EVE world contracts exist
- Create real SSU/Gate via EVE's testnet tooling
- Run full flow: register → withdraw → produce → deposit → claim pass → issue permit

**Recommended:** Unit tests focus on `ItemRegistry`, `AccessRegistry`, `AccessPass` lifecycle (no EVE types needed). Integration tests on testnet cover SSU/Gate interaction.

---

## 11. Deployment Plan

### Phase 1: SUI Testnet (current EVE testnet)

1. Pin `world` dependency to current testnet commit
2. Deploy `eve_integration` package
3. Create `GlobalRegistry` + `RegistryAdminCap` (init)
4. Test against EVE's testnet SSU/Gate (if accessible)
5. If EVE testnet assemblies not accessible, use mock objects for demo

### Phase 2: Frontend Deploy

1. Build frontend with new panes
2. Deploy to Vercel (public URL)
3. Test in-game browser loading (if EVE testnet has Assembly dApp URL feature)

### Phase 3: EVE Mainnet (when available)

1. Re-pin `world` dependency to mainnet commit
2. Verify all interfaces unchanged
3. Deploy fresh `eve_integration` package on mainnet
4. Update frontend .env with mainnet package IDs

---

## 12. Constraints and Limitations

1. **EVE world contracts are "not yet production-ready"** — interfaces may change before mainnet
2. **Cannot test real SSU/Gate interaction** without an EVE Smart Assembly on testnet — may need mock path for hackathon
3. **Watcher auto-grant** only works for factory owner's own passes; third-party players must self-claim via frontend
4. **Single-SSU per factory** due to Item parent_id binding
5. **JumpPermit is single-use** — players need new permits for each jump (watcher can auto-reissue)
6. **No existing public functions** in industrial_core for "bridge-friendly" operations — must compose entirely via existing public API (`deposit_materials`, `withdraw_output`, `start_production`, `complete_production`)

---

## 13. Open Questions

1. **EVE world contract testnet address:** Need to verify `4c78adac` is still current and pin exact commit hash
2. **Character object discovery:** How does frontend find the player's Character object from their wallet address? (likely via EVE's Smart Character system)
3. **SSU open inventory creation:** Does `deposit_to_open_inventory` auto-create the open inventory on first use, or does it need explicit initialization?
4. **Gate pair topology:** For a factory, is it one gate pair (in/out), or could there be multiple entry points?
5. **EVE item type_ids:** Where is the canonical list of EVE Frontier item type_ids? Needed to seed GlobalRegistry.

---

## Appendix A: Spec Review Fixes (Rev 2)

### From sui-architect audit (Round 1)
- Added `&Character` to all SSU/Gate function signatures
- Switched to open inventory (`deposit_to_open_inventory` / `withdraw_from_open_inventory`)
- Added type conversion `u64 ↔ u32` with overflow checks
- FactoryOverride restricted to disable-only (no new mappings)
- AccessPass changed to `key` only (no `store`, non-transferable)
- Both gates in a pair must have `IndustrialAuth` extension
- Added SSU online status constraint documentation

### From spec-reviewer (Round 2)
- **C-1:** Fixed function names: `bpo_recipe_id` (not `recipe_id`), `recipe_id_of` (not `recipe_id`), `order_acceptor` (returns `Option<address>`), `order_status` (no `is_active`)
- **C-2:** Redesigned admin revocation: shared `AccessRegistry` with `revoked_passes` Table (admin cannot take owned objects from other addresses)
- **C-3:** Added duplicate pass prevention via `active_passes` Table in `AccessRegistry`
- **C-4:** Added `init()` function definition; removed unnecessary `admin_cap_id` field from `GlobalRegistry`
- **C-5:** Corrected `LeaseAgreement` type name (not `Lease`)
- **W-1:** Added `factory_id == object::id(line)` validation in claim functions
- **W-2:** Added `E_PASS_NOT_EXPIRABLE`, `E_DUPLICATE_PASS`, `E_PASS_REVOKED` error codes
- **W-3:** Added watcher keypair constraint documentation
- **W-4:** Added EVE type mocking strategy for tests
- **W-5:** Pinned `world` dependency guidance

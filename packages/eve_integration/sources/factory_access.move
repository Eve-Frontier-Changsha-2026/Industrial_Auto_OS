module eve_integration::factory_access;

use std::string::{Self, String};
use sui::event;
use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use industrial_core::blueprint::{Self, BlueprintOriginal};
use industrial_core::production_line::{Self, ProductionLine};
use marketplace::lease::{Self, LeaseAgreement};
use work_order::work_order::{Self, WorkOrder};

// === Error Codes ===
const E_RECIPE_MISMATCH: u64 = 2001;
const E_LEASE_NOT_ACTIVE: u64 = 2002;
const E_NOT_LESSEE: u64 = 2003;
const E_WO_NOT_ACTIVE: u64 = 2004;
const E_NOT_ACCEPTOR: u64 = 2005;
const E_NOT_PASS_HOLDER: u64 = 2006;
#[allow(unused_const)]
const E_PASS_EXPIRED: u64 = 2007;
const E_NOT_YET_EXPIRED: u64 = 2008;
#[allow(unused_const)]
const E_FACTORY_MISMATCH: u64 = 2009;
const E_PASS_NOT_EXPIRABLE: u64 = 2010;
const E_DUPLICATE_PASS: u64 = 2011;
#[allow(unused_const)]
const E_PASS_REVOKED: u64 = 2012;
const E_NOT_AUTHORIZED: u64 = 2013;

// === Constants ===
const PASS_TYPE_BLUEPRINT: u8 = 0;
const PASS_TYPE_LEASE: u8 = 1;
const PASS_TYPE_WORK_ORDER: u8 = 2;
#[allow(unused_const)]
const PERMIT_DURATION_MS: u64 = 3_600_000; // 1 hour

// === Events (must be in same module to emit) ===
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
    event::emit(AccessGrantedEvent {
        pass_id, factory_id, holder: ctx.sender(), pass_type: PASS_TYPE_BLUEPRINT, expires_at: option::none(),
    });
    transfer::transfer(pass, ctx.sender());
}

public fun claim_from_lease(
    access_registry: &mut AccessRegistry,
    lease_agreement: &LeaseAgreement,
    line: &ProductionLine,
    ctx: &mut TxContext,
) {
    let factory_id = object::id(line);
    assert!(lease::is_active(lease_agreement), E_LEASE_NOT_ACTIVE);
    assert!(lease::lessee(lease_agreement) == ctx.sender(), E_NOT_LESSEE);
    assert!(!has_active_pass(access_registry, factory_id, ctx.sender()), E_DUPLICATE_PASS);

    let expiry = lease::expiry(lease_agreement);
    let pass = AccessPass {
        id: object::new(ctx),
        factory_id,
        holder: ctx.sender(),
        pass_type: PASS_TYPE_LEASE,
        expires_at: option::some(expiry),
    };
    let pass_id = object::id(&pass);
    register_pass(access_registry, factory_id, ctx.sender(), pass_id);
    event::emit(AccessGrantedEvent {
        pass_id, factory_id, holder: ctx.sender(), pass_type: PASS_TYPE_LEASE, expires_at: option::some(expiry),
    });
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
    event::emit(AccessGrantedEvent {
        pass_id, factory_id, holder: ctx.sender(), pass_type: PASS_TYPE_WORK_ORDER, expires_at: option::none(),
    });
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
    event::emit(AccessRevokedEvent {
        pass_id, factory_id, holder, reason: string::utf8(b"surrender"),
    });
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
    event::emit(AccessRevokedEvent {
        pass_id, factory_id, holder, reason: string::utf8(b"expired"),
    });
    let AccessPass { id, factory_id: _, holder: _, pass_type: _, expires_at: _ } = pass;
    object::delete(id);
}

public fun admin_revoke_pass(
    access_registry: &mut AccessRegistry,
    pass_id: ID,
    holder: address,
    line: &ProductionLine,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == production_line::owner(line), E_NOT_AUTHORIZED);
    access_registry.revoked_passes.add(pass_id, true);
    unregister_pass(access_registry, object::id(line), holder);
    event::emit(AccessRevokedEvent {
        pass_id, factory_id: object::id(line), holder, reason: string::utf8(b"admin_revoke"),
    });
}

// === Query ===

public fun is_pass_revoked(registry: &AccessRegistry, pass_id: ID): bool {
    registry.revoked_passes.contains(pass_id)
}

// === Gate Permit (placeholder — requires world::gate types) ===

// === Accessors ===
public fun pass_factory_id(pass: &AccessPass): ID { pass.factory_id }
public fun pass_holder(pass: &AccessPass): address { pass.holder }
public fun pass_type(pass: &AccessPass): u8 { pass.pass_type }
public fun pass_expires_at(pass: &AccessPass): Option<u64> { pass.expires_at }

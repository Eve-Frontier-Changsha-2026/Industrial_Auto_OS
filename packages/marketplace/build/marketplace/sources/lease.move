module marketplace::lease;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::dynamic_object_field as dof;
use industrial_core::blueprint::BlueprintOriginal;
use industrial_core::production_line::{Self, ProductionLine};
use industrial_core::recipe::Recipe;

// === Error Codes ===
const E_NOT_LESSEE: u64 = 300;
const E_NOT_LESSOR: u64 = 301;
const E_LEASE_NOT_EXPIRED: u64 = 302;
const E_LEASE_INACTIVE: u64 = 303;
const E_LEASE_EXPIRED: u64 = 304;

// === DOF Key ===
public struct LeasedBpoKey has copy, drop, store {}

// === Structs ===

public struct LeaseAgreement has key {
    id: UID,
    lessor: address,
    lessee: address,
    deposit: Balance<SUI>,
    expiry: u64,
    daily_rate: u64,
    active: bool,
}

// === Events ===

public struct LeaseCreated has copy, drop {
    lease_id: ID,
    lessor: address,
    lessee: address,
    expiry: u64,
    daily_rate: u64,
}

public struct LeaseReturned has copy, drop {
    lease_id: ID,
    lessor: address,
    lessee: address,
}

public struct LeaseForfeited has copy, drop {
    lease_id: ID,
    lessor: address,
    lessee: address,
}

// === Functions ===

/// Create a lease agreement. Lessor wraps BPO and sets terms.
/// BPO is stored as a dynamic object field on the lease.
public fun create_lease(
    bpo: BlueprintOriginal,
    lessee: address,
    deposit_coin: Coin<SUI>,
    expiry: u64,
    daily_rate: u64,
    ctx: &mut TxContext,
) {
    let lessor = ctx.sender();
    let mut lease = LeaseAgreement {
        id: object::new(ctx),
        lessor,
        lessee,
        deposit: coin::into_balance(deposit_coin),
        expiry,
        daily_rate,
        active: true,
    };
    dof::add(&mut lease.id, LeasedBpoKey {}, bpo);
    let lease_id = object::id(&lease);
    sui::event::emit(LeaseCreated {
        lease_id,
        lessor,
        lessee,
        expiry,
        daily_rate,
    });
    transfer::share_object(lease);
}

/// Lessee returns BPO before expiry. BPO goes to lessor, deposit returned to lessee.
public fun return_lease(lease: &mut LeaseAgreement, ctx: &mut TxContext) {
    assert!(lease.active, E_LEASE_INACTIVE);
    assert!(ctx.sender() == lease.lessee, E_NOT_LESSEE);

    lease.active = false;
    let lease_id = lease.id.to_inner();
    let lessor = lease.lessor;
    let lessee = lease.lessee;

    sui::event::emit(LeaseReturned { lease_id, lessor, lessee });

    let bpo: BlueprintOriginal = dof::remove(&mut lease.id, LeasedBpoKey {});
    transfer::public_transfer(bpo, lessor);

    let amount = balance::value(&lease.deposit);
    let deposit_bal = balance::split(&mut lease.deposit, amount);
    let deposit_coin = coin::from_balance(deposit_bal, ctx);
    transfer::public_transfer(deposit_coin, lessee);
}

/// Lessor forfeits lease after expiry. BPO and deposit both go to lessor.
public fun forfeit_lease(lease: &mut LeaseAgreement, clock: &Clock, ctx: &mut TxContext) {
    assert!(lease.active, E_LEASE_INACTIVE);
    assert!(ctx.sender() == lease.lessor, E_NOT_LESSOR);
    assert!(clock.timestamp_ms() > lease.expiry, E_LEASE_NOT_EXPIRED);

    lease.active = false;
    let lease_id = lease.id.to_inner();
    let lessor = lease.lessor;
    let lessee = lease.lessee;

    sui::event::emit(LeaseForfeited { lease_id, lessor, lessee });

    let bpo: BlueprintOriginal = dof::remove(&mut lease.id, LeasedBpoKey {});
    transfer::public_transfer(bpo, lessor);

    let amount = balance::value(&lease.deposit);
    let deposit_bal = balance::split(&mut lease.deposit, amount);
    let deposit_coin = coin::from_balance(deposit_bal, ctx);
    transfer::public_transfer(deposit_coin, lessor);
}

/// Lessee starts production using the leased BPO.
/// Borrows BPO from DOF within this function frame — no cross-PTB reference issue.
/// Checks: active, lessee auth, not expired.
public fun start_production_with_lease(
    lease: &LeaseAgreement,
    line: &mut ProductionLine,
    recipe: &Recipe,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(lease.active, E_LEASE_INACTIVE);
    assert!(ctx.sender() == lease.lessee, E_NOT_LESSEE);
    assert!(clock.timestamp_ms() <= lease.expiry, E_LEASE_EXPIRED);

    let bpo: &BlueprintOriginal = dof::borrow(&lease.id, LeasedBpoKey {});
    production_line::start_production(line, recipe, bpo, clock, ctx);
}

// === Accessors ===

public fun lessor(lease: &LeaseAgreement): address { lease.lessor }
public fun lessee(lease: &LeaseAgreement): address { lease.lessee }
public fun expiry(lease: &LeaseAgreement): u64 { lease.expiry }
public fun daily_rate(lease: &LeaseAgreement): u64 { lease.daily_rate }
public fun deposit_value(lease: &LeaseAgreement): u64 { balance::value(&lease.deposit) }
public fun is_active(lease: &LeaseAgreement): bool { lease.active }

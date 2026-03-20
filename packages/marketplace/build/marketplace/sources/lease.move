module marketplace::lease;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use industrial_core::blueprint::BlueprintOriginal;

// === Error Codes ===
const E_NOT_LESSEE: u64 = 300;
const E_NOT_LESSOR: u64 = 301;
const E_LEASE_NOT_EXPIRED: u64 = 302;

// === Structs ===

public struct LeaseAgreement has key {
    id: UID,
    lessor: address,
    lessee: address,
    bpo: BlueprintOriginal,
    deposit: Balance<SUI>,
    expiry: u64,
    daily_rate: u64,
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
public fun create_lease(
    bpo: BlueprintOriginal,
    lessee: address,
    deposit_coin: Coin<SUI>,
    expiry: u64,
    daily_rate: u64,
    ctx: &mut TxContext,
) {
    let lessor = ctx.sender();
    let lease = LeaseAgreement {
        id: object::new(ctx),
        lessor,
        lessee,
        bpo,
        deposit: coin::into_balance(deposit_coin),
        expiry,
        daily_rate,
    };
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
public fun return_lease(lease: LeaseAgreement, ctx: &mut TxContext) {
    assert!(ctx.sender() == lease.lessee, E_NOT_LESSEE);

    let LeaseAgreement { id, lessor, lessee, bpo, deposit, expiry: _, daily_rate: _ } = lease;
    let lease_id = id.to_inner();

    sui::event::emit(LeaseReturned { lease_id, lessor, lessee });

    transfer::public_transfer(bpo, lessor);
    let deposit_coin = coin::from_balance(deposit, ctx);
    transfer::public_transfer(deposit_coin, lessee);
    id.delete();
}

/// Lessor forfeits lease after expiry. BPO and deposit both go to lessor.
public fun forfeit_lease(lease: LeaseAgreement, clock: &Clock, ctx: &mut TxContext) {
    assert!(ctx.sender() == lease.lessor, E_NOT_LESSOR);
    assert!(clock.timestamp_ms() > lease.expiry, E_LEASE_NOT_EXPIRED);

    let LeaseAgreement { id, lessor, lessee, bpo, deposit, expiry: _, daily_rate: _ } = lease;
    let lease_id = id.to_inner();

    sui::event::emit(LeaseForfeited { lease_id, lessor, lessee });

    transfer::public_transfer(bpo, lessor);
    let deposit_coin = coin::from_balance(deposit, ctx);
    transfer::public_transfer(deposit_coin, lessor);
    id.delete();
}

// === Accessors ===

public fun lessor(lease: &LeaseAgreement): address { lease.lessor }
public fun lessee(lease: &LeaseAgreement): address { lease.lessee }
public fun expiry(lease: &LeaseAgreement): u64 { lease.expiry }
public fun daily_rate(lease: &LeaseAgreement): u64 { lease.daily_rate }
public fun deposit_value(lease: &LeaseAgreement): u64 { balance::value(&lease.deposit) }

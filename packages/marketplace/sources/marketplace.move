module marketplace::marketplace;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::dynamic_object_field as dof;
use industrial_core::blueprint::{BlueprintOriginal, BlueprintCopy};

// === Error Codes ===
const E_LISTING_PRICE_TOO_LOW: u64 = 200;
const E_NOT_SELLER: u64 = 201;
const E_INSUFFICIENT_PAYMENT: u64 = 202;
const E_FEE_TOO_HIGH: u64 = 203;
const E_LISTING_INACTIVE: u64 = 204;

// === Constants ===
const MIN_PRICE: u64 = 1_000_000;
const DEFAULT_FEE_BPS: u64 = 250;
const MAX_FEE_BPS: u64 = 1000;

// === DOF Key Types ===
public struct ListedBpo has copy, drop, store {}
public struct ListedBpc has copy, drop, store {}

// === Structs ===

public struct MarketplaceAdminCap has key, store {
    id: UID,
}

public struct Marketplace has key {
    id: UID,
    fee_bps: u64,
    collected_fees: Balance<SUI>,
}

public struct BpoListing has key {
    id: UID,
    seller: address,
    price: u64,
    active: bool,
}

public struct BpcListing has key {
    id: UID,
    seller: address,
    price: u64,
    active: bool,
}

// === Events ===

public struct BpoListed has copy, drop {
    listing_id: ID,
    seller: address,
    bpo_id: ID,
    price: u64,
}

public struct BpoSold has copy, drop {
    listing_id: ID,
    seller: address,
    buyer: address,
    price: u64,
    fee: u64,
}

public struct BpoDelisted has copy, drop {
    listing_id: ID,
    seller: address,
}

public struct BpcListed has copy, drop {
    listing_id: ID,
    seller: address,
    bpc_id: ID,
    price: u64,
}

public struct BpcSold has copy, drop {
    listing_id: ID,
    seller: address,
    buyer: address,
    price: u64,
    fee: u64,
}

public struct BpcDelisted has copy, drop {
    listing_id: ID,
    seller: address,
}

// === Init ===

fun init(ctx: &mut TxContext) {
    let admin_cap = MarketplaceAdminCap { id: object::new(ctx) };
    transfer::transfer(admin_cap, ctx.sender());

    let market = Marketplace {
        id: object::new(ctx),
        fee_bps: DEFAULT_FEE_BPS,
        collected_fees: balance::zero(),
    };
    transfer::share_object(market);
}

// === Admin Functions ===

/// Update marketplace fee. Max 10%.
public fun update_fee(
    market: &mut Marketplace,
    _cap: &MarketplaceAdminCap,
    new_bps: u64,
) {
    assert!(new_bps <= MAX_FEE_BPS, E_FEE_TOO_HIGH);
    market.fee_bps = new_bps;
}

/// Withdraw all accumulated fees.
public fun withdraw_fees(
    market: &mut Marketplace,
    _cap: &MarketplaceAdminCap,
    ctx: &mut TxContext,
): Coin<SUI> {
    let amount = balance::value(&market.collected_fees);
    let bal = balance::split(&mut market.collected_fees, amount);
    coin::from_balance(bal, ctx)
}

// === BPO Listing ===

/// List a BPO for sale. Price must be >= MIN_PRICE.
/// BPO is stored as a dynamic object field on the listing.
public fun list_bpo(
    _market: &Marketplace,
    bpo: BlueprintOriginal,
    price: u64,
    ctx: &mut TxContext,
) {
    assert!(price >= MIN_PRICE, E_LISTING_PRICE_TOO_LOW);
    let bpo_id = object::id(&bpo);
    let mut listing = BpoListing {
        id: object::new(ctx),
        seller: ctx.sender(),
        price,
        active: true,
    };
    dof::add(&mut listing.id, ListedBpo {}, bpo);
    let listing_id = object::id(&listing);
    sui::event::emit(BpoListed {
        listing_id,
        seller: ctx.sender(),
        bpo_id,
        price,
    });
    transfer::share_object(listing);
}

/// Delist a BPO listing. Only seller can delist.
public fun delist_bpo(listing: &mut BpoListing, ctx: &TxContext): BlueprintOriginal {
    assert!(listing.active, E_LISTING_INACTIVE);
    assert!(ctx.sender() == listing.seller, E_NOT_SELLER);
    listing.active = false;
    let listing_id = listing.id.to_inner();
    sui::event::emit(BpoDelisted { listing_id, seller: listing.seller });
    dof::remove(&mut listing.id, ListedBpo {})
}

/// Buy a BPO. Payment coin is debited by listing price; fee goes to marketplace.
public fun buy_bpo(
    market: &mut Marketplace,
    listing: &mut BpoListing,
    payment: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(listing.active, E_LISTING_INACTIVE);
    let price = listing.price;
    assert!(coin::value(payment) >= price, E_INSUFFICIENT_PAYMENT);

    let fee_bps = market.fee_bps;
    let fee = if (price * fee_bps / 10000 == 0) { 1 } else { price * fee_bps / 10000 };

    // Split fee into marketplace
    let fee_bal = coin::split(payment, fee, ctx);
    balance::join(&mut market.collected_fees, coin::into_balance(fee_bal));

    // Pay seller (price - fee)
    let seller_amount = price - fee;
    let seller_coin = coin::split(payment, seller_amount, ctx);

    listing.active = false;
    let listing_id = listing.id.to_inner();
    let seller = listing.seller;
    let bpo: BlueprintOriginal = dof::remove(&mut listing.id, ListedBpo {});

    sui::event::emit(BpoSold {
        listing_id,
        seller,
        buyer: ctx.sender(),
        price,
        fee,
    });

    transfer::public_transfer(seller_coin, seller);
    transfer::public_transfer(bpo, ctx.sender());
}

// === BPC Listing ===

/// List a BPC for sale. Price must be >= MIN_PRICE.
/// BPC is stored as a dynamic object field on the listing.
public fun list_bpc(
    _market: &Marketplace,
    bpc: BlueprintCopy,
    price: u64,
    ctx: &mut TxContext,
) {
    assert!(price >= MIN_PRICE, E_LISTING_PRICE_TOO_LOW);
    let bpc_id = object::id(&bpc);
    let mut listing = BpcListing {
        id: object::new(ctx),
        seller: ctx.sender(),
        price,
        active: true,
    };
    dof::add(&mut listing.id, ListedBpc {}, bpc);
    let listing_id = object::id(&listing);
    sui::event::emit(BpcListed {
        listing_id,
        seller: ctx.sender(),
        bpc_id,
        price,
    });
    transfer::share_object(listing);
}

/// Delist a BPC listing. Only seller can delist.
public fun delist_bpc(listing: &mut BpcListing, ctx: &TxContext): BlueprintCopy {
    assert!(listing.active, E_LISTING_INACTIVE);
    assert!(ctx.sender() == listing.seller, E_NOT_SELLER);
    listing.active = false;
    let listing_id = listing.id.to_inner();
    sui::event::emit(BpcDelisted { listing_id, seller: listing.seller });
    dof::remove(&mut listing.id, ListedBpc {})
}

/// Buy a BPC. Payment coin is debited by listing price; fee goes to marketplace.
public fun buy_bpc(
    market: &mut Marketplace,
    listing: &mut BpcListing,
    payment: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(listing.active, E_LISTING_INACTIVE);
    let price = listing.price;
    assert!(coin::value(payment) >= price, E_INSUFFICIENT_PAYMENT);

    let fee_bps = market.fee_bps;
    let fee = if (price * fee_bps / 10000 == 0) { 1 } else { price * fee_bps / 10000 };

    // Split fee into marketplace
    let fee_bal = coin::split(payment, fee, ctx);
    balance::join(&mut market.collected_fees, coin::into_balance(fee_bal));

    // Pay seller (price - fee)
    let seller_amount = price - fee;
    let seller_coin = coin::split(payment, seller_amount, ctx);

    listing.active = false;
    let listing_id = listing.id.to_inner();
    let seller = listing.seller;
    let bpc: BlueprintCopy = dof::remove(&mut listing.id, ListedBpc {});

    sui::event::emit(BpcSold {
        listing_id,
        seller,
        buyer: ctx.sender(),
        price,
        fee,
    });

    transfer::public_transfer(seller_coin, seller);
    transfer::public_transfer(bpc, ctx.sender());
}

// === Test Helpers ===

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx);
}

// === Accessors ===

public fun fee_bps(market: &Marketplace): u64 { market.fee_bps }
public fun collected_fees_value(market: &Marketplace): u64 { balance::value(&market.collected_fees) }

public fun bpo_listing_seller(listing: &BpoListing): address { listing.seller }
public fun bpo_listing_price(listing: &BpoListing): u64 { listing.price }
public fun bpo_listing_active(listing: &BpoListing): bool { listing.active }

public fun bpc_listing_seller(listing: &BpcListing): address { listing.seller }
public fun bpc_listing_price(listing: &BpcListing): u64 { listing.price }
public fun bpc_listing_active(listing: &BpcListing): bool { listing.active }

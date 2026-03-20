module marketplace::marketplace;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use industrial_core::blueprint::{BlueprintOriginal, BlueprintCopy};

// === Error Codes ===
const E_LISTING_PRICE_TOO_LOW: u64 = 200;
const E_NOT_SELLER: u64 = 201;
const E_INSUFFICIENT_PAYMENT: u64 = 202;
const E_FEE_TOO_HIGH: u64 = 203;

// === Constants ===
const MIN_PRICE: u64 = 1_000_000;
const DEFAULT_FEE_BPS: u64 = 250;
const MAX_FEE_BPS: u64 = 1000;

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
    bpo: BlueprintOriginal,
    price: u64,
}

public struct BpcListing has key {
    id: UID,
    seller: address,
    bpc: BlueprintCopy,
    price: u64,
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
public fun list_bpo(
    _market: &Marketplace,
    bpo: BlueprintOriginal,
    price: u64,
    ctx: &mut TxContext,
) {
    assert!(price >= MIN_PRICE, E_LISTING_PRICE_TOO_LOW);
    let bpo_id = object::id(&bpo);
    let listing = BpoListing {
        id: object::new(ctx),
        seller: ctx.sender(),
        bpo,
        price,
    };
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
public fun delist_bpo(listing: BpoListing, ctx: &TxContext): BlueprintOriginal {
    assert!(ctx.sender() == listing.seller, E_NOT_SELLER);
    let BpoListing { id, seller, bpo, price: _ } = listing;
    let listing_id = id.to_inner();
    sui::event::emit(BpoDelisted { listing_id, seller });
    id.delete();
    bpo
}

/// Buy a BPO. Payment coin is debited by listing price; fee goes to marketplace.
public fun buy_bpo(
    market: &mut Marketplace,
    listing: BpoListing,
    payment: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
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

    let BpoListing { id, seller, bpo, price: _ } = listing;
    let listing_id = id.to_inner();

    sui::event::emit(BpoSold {
        listing_id,
        seller,
        buyer: ctx.sender(),
        price,
        fee,
    });

    transfer::public_transfer(seller_coin, seller);
    transfer::public_transfer(bpo, ctx.sender());
    id.delete();
}

// === BPC Listing ===

/// List a BPC for sale. Price must be >= MIN_PRICE.
public fun list_bpc(
    _market: &Marketplace,
    bpc: BlueprintCopy,
    price: u64,
    ctx: &mut TxContext,
) {
    assert!(price >= MIN_PRICE, E_LISTING_PRICE_TOO_LOW);
    let bpc_id = object::id(&bpc);
    let listing = BpcListing {
        id: object::new(ctx),
        seller: ctx.sender(),
        bpc,
        price,
    };
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
public fun delist_bpc(listing: BpcListing, ctx: &TxContext): BlueprintCopy {
    assert!(ctx.sender() == listing.seller, E_NOT_SELLER);
    let BpcListing { id, seller, bpc, price: _ } = listing;
    let listing_id = id.to_inner();
    sui::event::emit(BpcDelisted { listing_id, seller });
    id.delete();
    bpc
}

/// Buy a BPC. Payment coin is debited by listing price; fee goes to marketplace.
public fun buy_bpc(
    market: &mut Marketplace,
    listing: BpcListing,
    payment: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
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

    let BpcListing { id, seller, bpc, price: _ } = listing;
    let listing_id = id.to_inner();

    sui::event::emit(BpcSold {
        listing_id,
        seller,
        buyer: ctx.sender(),
        price,
        fee,
    });

    transfer::public_transfer(seller_coin, seller);
    transfer::public_transfer(bpc, ctx.sender());
    id.delete();
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

public fun bpc_listing_seller(listing: &BpcListing): address { listing.seller }
public fun bpc_listing_price(listing: &BpcListing): u64 { listing.price }

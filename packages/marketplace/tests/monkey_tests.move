#[test_only]
module marketplace::monkey_tests;

use sui::clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use marketplace::marketplace::{Self, Marketplace, MarketplaceAdminCap, BpoListing, BpcListing};
use marketplace::lease::{Self, LeaseAgreement};
use std::unit_test::destroy;

const ADMIN: address = @0xAD;
const SELLER: address = @0xBE;
const BUYER: address = @0xCA;
const ATTACKER: address = @0xEE;
const LESSOR: address = @0xAA;
const LESSEE: address = @0xBB;

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

// ═══════════════════════════════════════════════════════════════════
// Marketplace — Boundary Values
// ═══════════════════════════════════════════════════════════════════

/// List at price = 0 → must abort E_LISTING_PRICE_TOO_LOW
#[test]
#[expected_failure(abort_code = 200)]
fun monkey_list_bpo_zero_price() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 0, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

/// List at price = MIN_PRICE - 1 (999_999) → must abort
#[test]
#[expected_failure(abort_code = 200)]
fun monkey_list_bpo_just_below_min_price() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 999_999, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

/// List at exactly MIN_PRICE → should succeed
#[test]
fun monkey_list_bpo_exact_min_price() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 1_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(SELLER);
    {
        let listing = scenario.take_shared<BpoListing>();
        assert!(marketplace::bpo_listing_price(&listing) == 1_000_000);
        test_scenario::return_shared(listing);
    };
    scenario.end();
}

/// List BPC at price = 0 → must abort
#[test]
#[expected_failure(abort_code = 200)]
fun monkey_list_bpc_zero_price() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let mut bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let bpc = blueprint::mint_bpc(&mut bpo, 5, scenario.ctx());
        marketplace::list_bpc(&market, bpc, 0, scenario.ctx());
        destroy(r);
        destroy(bpo);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

// ═══════════════════════════════════════════════════════════════════
// Marketplace — Payment Attacks
// ═══════════════════════════════════════════════════════════════════

/// Buy BPO with insufficient payment → must abort E_INSUFFICIENT_PAYMENT
#[test]
#[expected_failure(abort_code = 202)]
fun monkey_buy_bpo_insufficient_payment() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 10_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(9_999_999, scenario.ctx());
        marketplace::buy_bpo(&mut market, listing, &mut payment, scenario.ctx());
        destroy(payment);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

/// Buy BPO with zero coin → must abort E_INSUFFICIENT_PAYMENT
#[test]
#[expected_failure(abort_code = 202)]
fun monkey_buy_bpo_zero_coin() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 1_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(0, scenario.ctx());
        marketplace::buy_bpo(&mut market, listing, &mut payment, scenario.ctx());
        destroy(payment);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

/// Buy BPC with insufficient payment → must abort E_INSUFFICIENT_PAYMENT
#[test]
#[expected_failure(abort_code = 202)]
fun monkey_buy_bpc_insufficient_payment() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let mut bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let bpc = blueprint::mint_bpc(&mut bpo, 5, scenario.ctx());
        marketplace::list_bpc(&market, bpc, 5_000_000, scenario.ctx());
        destroy(r);
        destroy(bpo);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let listing = scenario.take_shared<BpcListing>();
        let mut payment = coin::mint_for_testing<SUI>(1, scenario.ctx());
        marketplace::buy_bpc(&mut market, listing, &mut payment, scenario.ctx());
        destroy(payment);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

// ═══════════════════════════════════════════════════════════════════
// Marketplace — Permission Attacks
// ═══════════════════════════════════════════════════════════════════

/// Attacker (non-seller) tries to delist BPC → must abort E_NOT_SELLER
#[test]
#[expected_failure(abort_code = 201)]
fun monkey_delist_bpc_by_attacker() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let mut bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let bpc = blueprint::mint_bpc(&mut bpo, 5, scenario.ctx());
        marketplace::list_bpc(&market, bpc, 2_000_000, scenario.ctx());
        destroy(r);
        destroy(bpo);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(ATTACKER);
    {
        let listing = scenario.take_shared<BpcListing>();
        let bpc = marketplace::delist_bpc(listing, scenario.ctx());
        destroy(bpc);
    };
    scenario.end();
}

/// BUYER (non-seller) tries to delist BPO they just missed buying → abort
#[test]
#[expected_failure(abort_code = 201)]
fun monkey_delist_bpo_by_buyer() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 5_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(BUYER);
    {
        let listing = scenario.take_shared<BpoListing>();
        let bpo = marketplace::delist_bpo(listing, scenario.ctx());
        destroy(bpo);
    };
    scenario.end();
}

// ═══════════════════════════════════════════════════════════════════
// Marketplace — Fee Edge Cases
// ═══════════════════════════════════════════════════════════════════

/// Set fee to exactly MAX (1000 bps = 10%) → should succeed
#[test]
fun monkey_fee_at_max_boundary() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        marketplace::update_fee(&mut market, &cap, 1000);
        assert!(marketplace::fee_bps(&market) == 1000);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };

    // Buy with 10% fee
    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 10_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(10_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, listing, &mut payment, scenario.ctx());
        // fee = 10_000_000 * 1000 / 10000 = 1_000_000
        assert!(marketplace::collected_fees_value(&market) == 1_000_000);
        destroy(payment);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(SELLER);
    {
        let seller_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&seller_coin) == 9_000_000);
        scenario.return_to_sender(seller_coin);
    };
    scenario.end();
}

/// Set fee above MAX (1001) → must abort E_FEE_TOO_HIGH
#[test]
#[expected_failure(abort_code = 203)]
fun monkey_fee_above_max_by_one() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        marketplace::update_fee(&mut market, &cap, 1001);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

/// Set fee to MAX_U64 → must abort E_FEE_TOO_HIGH
#[test]
#[expected_failure(abort_code = 203)]
fun monkey_fee_max_u64() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        marketplace::update_fee(&mut market, &cap, 18446744073709551615);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

/// Set fee to 0 bps → buy should still charge min fee of 1
#[test]
fun monkey_fee_zero_bps_min_fee_enforced() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        marketplace::update_fee(&mut market, &cap, 0);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let mut bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let bpc = blueprint::mint_bpc(&mut bpo, 5, scenario.ctx());
        marketplace::list_bpc(&market, bpc, 1_000_000, scenario.ctx());
        destroy(r);
        destroy(bpo);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let listing = scenario.take_shared<BpcListing>();
        let mut payment = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        marketplace::buy_bpc(&mut market, listing, &mut payment, scenario.ctx());
        // fee_bps=0, price*0/10000=0 → enforced min fee = 1
        assert!(marketplace::collected_fees_value(&market) == 1);
        destroy(payment);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

// ═══════════════════════════════════════════════════════════════════
// Marketplace — Lifecycle / Sequence Attacks
// ═══════════════════════════════════════════════════════════════════

/// Seller lists BPO, delists it, then relists it → should work
#[test]
fun monkey_list_delist_relist_bpo() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    // List
    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 5_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    // Delist
    scenario.next_tx(SELLER);
    let bpo_returned;
    {
        let listing = scenario.take_shared<BpoListing>();
        bpo_returned = marketplace::delist_bpo(listing, scenario.ctx());
    };

    // Relist at different price
    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        marketplace::list_bpo(&market, bpo_returned, 8_000_000, scenario.ctx());
        test_scenario::return_shared(market);
    };

    // Verify new listing
    scenario.next_tx(SELLER);
    {
        let listing = scenario.take_shared<BpoListing>();
        assert!(marketplace::bpo_listing_price(&listing) == 8_000_000);
        test_scenario::return_shared(listing);
    };
    scenario.end();
}

/// Buy BPO with huge overpayment → remaining coin should keep its value
#[test]
fun monkey_buy_bpo_massive_overpayment() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 1_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let listing = scenario.take_shared<BpoListing>();
        // Overpay by 1000x
        let mut payment = coin::mint_for_testing<SUI>(1_000_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, listing, &mut payment, scenario.ctx());
        // remaining = 1_000_000_000 - 1_000_000 = 999_000_000
        assert!(coin::value(&payment) == 999_000_000);
        destroy(payment);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

/// Withdraw fees when zero fees collected → should return 0-value coin
#[test]
fun monkey_withdraw_fees_when_zero() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        let withdrawn = marketplace::withdraw_fees(&mut market, &cap, scenario.ctx());
        assert!(coin::value(&withdrawn) == 0);
        destroy(withdrawn);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

/// Multiple sequential buys accumulate fees correctly
#[test]
fun monkey_multiple_buys_accumulate_fees() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    // List BPO 1
    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 10_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    // Buy BPO 1
    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(10_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, listing, &mut payment, scenario.ctx());
        assert!(marketplace::collected_fees_value(&market) == 250_000);
        destroy(payment);
        test_scenario::return_shared(market);
    };

    // List BPO 2
    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 20_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    // Buy BPO 2
    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(20_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, listing, &mut payment, scenario.ctx());
        // accumulated: 250_000 + 500_000 = 750_000
        assert!(marketplace::collected_fees_value(&market) == 750_000);
        destroy(payment);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

// ═══════════════════════════════════════════════════════════════════
// Lease — Extreme Values
// ═══════════════════════════════════════════════════════════════════

/// Lease with 0 deposit → should still work (no validation on deposit)
#[test]
fun monkey_lease_zero_deposit() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(0, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 9999999, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSOR);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        assert!(lease::deposit_value(&agreement) == 0);
        test_scenario::return_shared(agreement);
    };
    scenario.end();
}

/// Lease with 0 daily_rate → should work (no validation)
#[test]
fun monkey_lease_zero_daily_rate() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 9999999, 0, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSOR);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        assert!(lease::daily_rate(&agreement) == 0);
        test_scenario::return_shared(agreement);
    };
    scenario.end();
}

/// Lease with expiry = 0 → lessor can forfeit immediately
#[test]
fun monkey_lease_expiry_zero_instant_forfeit() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 0, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSOR);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clk, 1); // 1ms > 0
        lease::forfeit_lease(agreement, &clk, scenario.ctx());
        clock::destroy_for_testing(clk);
    };

    scenario.next_tx(LESSOR);
    {
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        destroy(bpo);
        let deposit_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&deposit_coin) == 1_000_000);
        scenario.return_to_sender(deposit_coin);
    };
    scenario.end();
}

/// Forfeit at exact expiry time → should fail (need strictly greater than)
#[test]
#[expected_failure(abort_code = 302)]
fun monkey_forfeit_at_exact_expiry_boundary() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 5000, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSOR);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clk, 5000); // exactly at expiry, NOT past
        lease::forfeit_lease(agreement, &clk, scenario.ctx());
        clock::destroy_for_testing(clk);
    };
    scenario.end();
}

/// Lessee tries to forfeit their own lease → must abort E_NOT_LESSOR
#[test]
#[expected_failure(abort_code = 301)]
fun monkey_lessee_tries_to_forfeit() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 1000, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSEE); // Lessee, not lessor
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clk, 2000);
        lease::forfeit_lease(agreement, &clk, scenario.ctx());
        clock::destroy_for_testing(clk);
    };
    scenario.end();
}

/// Lessor tries to return a lease (only lessee can) → must abort E_NOT_LESSEE
#[test]
#[expected_failure(abort_code = 300)]
fun monkey_lessor_tries_to_return() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 999_999_999, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSOR); // Lessor, not lessee
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        lease::return_lease(agreement, scenario.ctx());
    };
    scenario.end();
}

/// Lease with MAX_U64 expiry → lessee can still return it normally
#[test]
fun monkey_lease_max_u64_expiry_return() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(500_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 18446744073709551615, 1, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSEE);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        assert!(lease::expiry(&agreement) == 18446744073709551615);
        lease::return_lease(agreement, scenario.ctx());
    };

    scenario.next_tx(LESSEE);
    {
        let deposit_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&deposit_coin) == 500_000);
        scenario.return_to_sender(deposit_coin);
    };
    scenario.end();
}

/// Lease with zero deposit — lessee returns, gets 0-value coin back
#[test]
fun monkey_lease_zero_deposit_return() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(0, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 999_999_999, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSEE);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        lease::return_lease(agreement, scenario.ctx());
    };

    // Deposit coin of 0 goes to lessee
    scenario.next_tx(LESSEE);
    {
        let deposit_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&deposit_coin) == 0);
        scenario.return_to_sender(deposit_coin);
    };
    scenario.end();
}

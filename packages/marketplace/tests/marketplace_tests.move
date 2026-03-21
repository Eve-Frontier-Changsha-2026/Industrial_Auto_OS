#[test_only]
module marketplace::marketplace_tests;

use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use marketplace::marketplace::{Self, Marketplace, MarketplaceAdminCap, BpoListing, BpcListing};
use std::unit_test::destroy;

const ADMIN: address = @0xAD;
const SELLER: address = @0xBE;
const BUYER: address = @0xCA;

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

// ─── Init ───

#[test]
fun test_init_creates_shared_marketplace() {
    let mut scenario = test_scenario::begin(ADMIN);
    {
        marketplace::test_init(scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        let market = scenario.take_shared<Marketplace>();
        assert!(marketplace::fee_bps(&market) == 250);
        test_scenario::return_shared(market);

        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        scenario.return_to_sender(cap);
    };
    scenario.end();
}

// ─── BPO Listing ───

#[test]
fun test_list_bpo_wraps_object() {
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

    scenario.next_tx(SELLER);
    {
        let listing = scenario.take_shared<BpoListing>();
        assert!(marketplace::bpo_listing_seller(&listing) == SELLER);
        assert!(marketplace::bpo_listing_price(&listing) == 5_000_000);
        assert!(marketplace::bpo_listing_active(&listing) == true);
        test_scenario::return_shared(listing);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 200)]
fun test_list_below_min_price() {
    let mut scenario = test_scenario::begin(SELLER);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 500_000, scenario.ctx()); // below MIN_PRICE
        destroy(r);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

#[test]
fun test_buy_bpo_fee_split() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    // SELLER lists BPO at 10_000_000 MIST
    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 10_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    // BUYER buys with exact payment
    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let mut listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(10_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, &mut listing, &mut payment, scenario.ctx());
        // fee = 10_000_000 * 250 / 10000 = 250_000
        assert!(marketplace::collected_fees_value(&market) == 250_000);
        assert!(marketplace::bpo_listing_active(&listing) == false);
        destroy(payment); // 0 left after exact payment
        test_scenario::return_shared(listing);
        test_scenario::return_shared(market);
    };

    // SELLER should have received 9_750_000
    scenario.next_tx(SELLER);
    {
        let seller_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&seller_coin) == 9_750_000);
        scenario.return_to_sender(seller_coin);
    };
    scenario.end();
}

#[test]
fun test_buy_bpo_min_fee_1_mist() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    // Admin sets fee to 0
    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        marketplace::update_fee(&mut market, &cap, 0);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };

    // SELLER lists at MIN_PRICE
    scenario.next_tx(SELLER);
    {
        let market = scenario.take_shared<Marketplace>();
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        marketplace::list_bpo(&market, bpo, 1_000_000, scenario.ctx());
        destroy(r);
        test_scenario::return_shared(market);
    };

    // BUYER buys — fee should be 1 (minimum) since 1_000_000 * 0 / 10000 == 0
    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let mut listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, &mut listing, &mut payment, scenario.ctx());
        assert!(marketplace::collected_fees_value(&market) == 1);
        destroy(payment);
        test_scenario::return_shared(listing);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(SELLER);
    {
        let seller_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&seller_coin) == 999_999); // price - 1 fee
        scenario.return_to_sender(seller_coin);
    };
    scenario.end();
}

#[test]
fun test_buy_bpo_overpayment_returns_change() {
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
        let mut listing = scenario.take_shared<BpoListing>();
        // overpay by 5_000_000
        let mut payment = coin::mint_for_testing<SUI>(15_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, &mut listing, &mut payment, scenario.ctx());
        // remaining should be 15_000_000 - 10_000_000 = 5_000_000
        assert!(coin::value(&payment) == 5_000_000);
        destroy(payment);
        test_scenario::return_shared(listing);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

#[test]
fun test_delist_bpo_by_seller() {
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

    scenario.next_tx(SELLER);
    {
        let mut listing = scenario.take_shared<BpoListing>();
        let bpo = marketplace::delist_bpo(&mut listing, scenario.ctx());
        assert!(marketplace::bpo_listing_active(&listing) == false);
        // BPO returned successfully
        destroy(bpo);
        test_scenario::return_shared(listing);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 201)]
fun test_delist_bpo_by_non_seller() {
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

    scenario.next_tx(BUYER); // BUYER tries to delist
    {
        let mut listing = scenario.take_shared<BpoListing>();
        let bpo = marketplace::delist_bpo(&mut listing, scenario.ctx());
        destroy(bpo);
        test_scenario::return_shared(listing);
    };
    scenario.end();
}

// ─── BPC Listing ───

#[test]
fun test_list_buy_bpc() {
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

    scenario.next_tx(SELLER);
    {
        let listing = scenario.take_shared<BpcListing>();
        assert!(marketplace::bpc_listing_seller(&listing) == SELLER);
        assert!(marketplace::bpc_listing_price(&listing) == 2_000_000);
        test_scenario::return_shared(listing);
    };

    scenario.next_tx(BUYER);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let mut listing = scenario.take_shared<BpcListing>();
        let mut payment = coin::mint_for_testing<SUI>(2_000_000, scenario.ctx());
        marketplace::buy_bpc(&mut market, &mut listing, &mut payment, scenario.ctx());
        // fee = 2_000_000 * 250 / 10000 = 50_000
        assert!(marketplace::collected_fees_value(&market) == 50_000);
        destroy(payment);
        test_scenario::return_shared(listing);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(SELLER);
    {
        let seller_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&seller_coin) == 1_950_000);
        scenario.return_to_sender(seller_coin);
    };
    scenario.end();
}

// ─── Admin ───

#[test]
fun test_update_fee() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        marketplace::update_fee(&mut market, &cap, 500); // 5%
        assert!(marketplace::fee_bps(&market) == 500);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };

    // SELLER lists, BUYER buys — fee should be 5%
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
        let mut listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(10_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, &mut listing, &mut payment, scenario.ctx());
        // fee = 10_000_000 * 500 / 10000 = 500_000
        assert!(marketplace::collected_fees_value(&market) == 500_000);
        destroy(payment);
        test_scenario::return_shared(listing);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 203)]
fun test_update_fee_too_high() {
    let mut scenario = test_scenario::begin(ADMIN);
    marketplace::test_init(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        marketplace::update_fee(&mut market, &cap, 1001); // over MAX_FEE_BPS
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

#[test]
fun test_withdraw_fees() {
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
        let mut listing = scenario.take_shared<BpoListing>();
        let mut payment = coin::mint_for_testing<SUI>(10_000_000, scenario.ctx());
        marketplace::buy_bpo(&mut market, &mut listing, &mut payment, scenario.ctx());
        destroy(payment);
        test_scenario::return_shared(listing);
        test_scenario::return_shared(market);
    };

    scenario.next_tx(ADMIN);
    {
        let mut market = scenario.take_shared<Marketplace>();
        let cap = scenario.take_from_sender<MarketplaceAdminCap>();
        let withdrawn = marketplace::withdraw_fees(&mut market, &cap, scenario.ctx());
        assert!(coin::value(&withdrawn) == 250_000); // 2.5% of 10_000_000
        assert!(marketplace::collected_fees_value(&market) == 0);
        destroy(withdrawn);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(market);
    };
    scenario.end();
}

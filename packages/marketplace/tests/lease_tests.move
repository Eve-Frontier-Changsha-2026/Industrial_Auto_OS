#[test_only]
module marketplace::lease_tests;

use sui::clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use marketplace::lease::{Self, LeaseAgreement};
use std::unit_test::destroy;

const LESSOR: address = @0xAA;
const LESSEE: address = @0xBB;
const STRANGER: address = @0xCC;

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

// ─── Create ───

#[test]
fun test_create_lease_wraps_bpo() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 9999999, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSOR);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        assert!(lease::lessor(&agreement) == LESSOR);
        assert!(lease::lessee(&agreement) == LESSEE);
        assert!(lease::expiry(&agreement) == 9999999);
        assert!(lease::daily_rate(&agreement) == 100_000);
        assert!(lease::deposit_value(&agreement) == 1_000_000);
        test_scenario::return_shared(agreement);
    };
    scenario.end();
}

// ─── Return ───

#[test]
fun test_return_lease_by_lessee() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(2_000_000, scenario.ctx());
        // expiry far in future
        lease::create_lease(bpo, LESSEE, deposit, 999_999_999_999, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSEE);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        lease::return_lease(agreement, scenario.ctx());
    };

    // BPO should go to LESSOR
    scenario.next_tx(LESSOR);
    {
        // LESSOR gets BPO back
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        destroy(bpo);
    };

    // Deposit should go to LESSEE
    scenario.next_tx(LESSEE);
    {
        let deposit_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&deposit_coin) == 2_000_000);
        scenario.return_to_sender(deposit_coin);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 300)]
fun test_return_lease_by_non_lessee() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 999_999_999_999, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(STRANGER); // STRANGER tries to return
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        lease::return_lease(agreement, scenario.ctx());
    };
    scenario.end();
}

// ─── Forfeit ───

#[test]
fun test_forfeit_lease_by_lessor_after_expiry() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(3_000_000, scenario.ctx());
        // expiry = 1000 ms
        lease::create_lease(bpo, LESSEE, deposit, 1000, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSOR);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        // Clock at 2000 ms > expiry 1000
        let mut clk = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clk, 2000);
        lease::forfeit_lease(agreement, &clk, scenario.ctx());
        clock::destroy_for_testing(clk);
    };

    // LESSOR gets BPO
    scenario.next_tx(LESSOR);
    {
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        destroy(bpo);
        let deposit_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(coin::value(&deposit_coin) == 3_000_000);
        scenario.return_to_sender(deposit_coin);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 302)]
fun test_forfeit_lease_before_expiry() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        // expiry = 999_999_999 ms (far future)
        lease::create_lease(bpo, LESSEE, deposit, 999_999_999, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(LESSOR);
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        // Clock at 1000 ms < expiry
        let mut clk = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clk, 1000);
        lease::forfeit_lease(agreement, &clk, scenario.ctx());
        clock::destroy_for_testing(clk);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 301)]
fun test_forfeit_by_non_lessor() {
    let mut scenario = test_scenario::begin(LESSOR);
    {
        let r = make_test_recipe(scenario.ctx());
        let bpo = blueprint::mint_bpo(&r, 10, 5, 5, scenario.ctx());
        let deposit = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        lease::create_lease(bpo, LESSEE, deposit, 1000, 100_000, scenario.ctx());
        destroy(r);
    };

    scenario.next_tx(STRANGER); // STRANGER tries to forfeit
    {
        let agreement = scenario.take_shared<LeaseAgreement>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clk, 2000);
        lease::forfeit_lease(agreement, &clk, scenario.ctx());
        clock::destroy_for_testing(clk);
    };
    scenario.end();
}

#[test_only]
module industrial_core::production_line_tests;

use sui::clock;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use industrial_core::production_line;
use std::unit_test::destroy;

const OWNER: address = @0xA;
const OPERATOR: address = @0xB;
const STRANGER: address = @0xC;

fun make_test_recipe(ctx: &mut TxContext): recipe::Recipe {
    recipe::create_recipe(
        b"Frigate Hull".to_string(),
        vector[
            recipe::new_material_req(101, 100),  // ore x100
            recipe::new_material_req(102, 50),   // crystal x50
        ],
        recipe::new_material_output(201, 1),     // hull x1
        60_000,  // 60s
        50,      // energy
        ctx,
    )
}

// ─── Create ───

#[test]
fun test_create_production_line() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line Alpha".to_string(), recipe_id, ctx);
    destroy(r);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    assert!(production_line::owner(&line) == OWNER);
    assert!(production_line::status(&line) == 0); // IDLE
    assert!(production_line::jobs_completed(&line) == 0);
    test_scenario::return_shared(line);
    scenario.end();
}

// ─── Operator Auth ───

#[test]
fun test_authorize_operator() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);
    destroy(r);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::authorize_operator(&mut line, OPERATOR, scenario.ctx());
    test_scenario::return_shared(line);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = production_line::E_NOT_OWNER)]
fun test_authorize_operator_by_non_owner_fails() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);
    destroy(r);

    scenario.next_tx(STRANGER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::authorize_operator(&mut line, OPERATOR, scenario.ctx());
    test_scenario::return_shared(line);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = production_line::E_MAX_OPERATORS_REACHED)]
fun test_max_operators_exceeded() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);
    destroy(r);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut i: u64 = 0;
    while (i < 11) { // 11 > MAX_OPERATORS(10)
        production_line::authorize_operator(&mut line, sui::address::from_u256((i + 1 as u256)), scenario.ctx());
        i = i + 1;
    };
    test_scenario::return_shared(line);
    scenario.end();
}

// ─── Deposit Materials ───

#[test]
fun test_deposit_materials_valid_item() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 101, 200, scenario.ctx());
    assert!(production_line::input_buffer_qty(&line, 101) == 200);
    test_scenario::return_shared(line);
    destroy(r);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = production_line::E_INVALID_ITEM_TYPE)]
fun test_deposit_materials_invalid_item() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 999, 200, scenario.ctx()); // 999 not in recipe
    test_scenario::return_shared(line);
    destroy(r);
    scenario.end();
}

// ─── Start + Complete Production ───

#[test]
fun test_start_and_complete_production() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    // Deposit materials + fuel
    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx()); // no efficiency
    production_line::deposit_materials(&mut line, &r, 101, 100, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 102, 50, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 50);

    // Start production
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 1); // RUNNING

    // Complete production after time passes
    clk.set_for_testing(1000 + 60_000); // exactly at job_end
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 0); // IDLE
    assert!(production_line::jobs_completed(&line) == 1);
    assert!(production_line::output_buffer_qty(&line, 201) == 1);

    // Withdraw
    production_line::withdraw_output(&mut line, 201, 1, scenario.ctx());
    assert!(production_line::output_buffer_qty(&line, 201) == 0);

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = production_line::E_INSUFFICIENT_MATERIALS)]
fun test_start_production_insufficient_materials() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 101, 50, scenario.ctx()); // only 50, need 100
    production_line::deposit_materials(&mut line, &r, 102, 50, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 50);

    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx()); // should fail

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = production_line::E_INSUFFICIENT_FUEL)]
fun test_start_production_insufficient_fuel() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 101, 100, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 102, 50, scenario.ctx());
    // No fuel deposited

    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = production_line::E_PRODUCTION_NOT_COMPLETE)]
fun test_complete_production_too_early() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 101, 100, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 102, 50, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 50);

    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    clk.set_for_testing(1000 + 30_000); // only half time
    production_line::complete_production(&mut line, &clk, scenario.ctx()); // should fail

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

// ─── Withdraw: Owner Only ───

#[test]
#[expected_failure(abort_code = production_line::E_NOT_OWNER)]
fun test_withdraw_output_operator_fails() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::authorize_operator(&mut line, OPERATOR, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 101, 100, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 102, 50, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 50);

    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    clk.set_for_testing(1000 + 60_000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    test_scenario::return_shared(line);

    // Operator tries to withdraw
    scenario.next_tx(OPERATOR);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::withdraw_output(&mut line, 201, 1, scenario.ctx()); // should fail
    test_scenario::return_shared(line);

    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

// ─── Efficiency Ceiling Division ───

#[test]
fun test_efficiency_ceiling_division() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    // Recipe: input qty=1, so with ME=25 → (1*75+99)/100 = 174/100 = 1 (ceiling)
    let r = recipe::create_recipe(
        b"Tiny Recipe".to_string(),
        vector[recipe::new_material_req(101, 1)],
        recipe::new_material_output(201, 1),
        10_000, // 10s
        10,
        ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 25, 25, scenario.ctx()); // max efficiency
    production_line::deposit_materials(&mut line, &r, 101, 1, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 10);

    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    // With TE=25: actual_duration = (10000*75+99)/100 = 750099/100 = 7501
    // job_end = 1000 + 7501 = 8501
    clk.set_for_testing(8501);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    assert!(production_line::output_buffer_qty(&line, 201) == 1);

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

// ─── Operator Can Start/Complete Production ───

#[test]
fun test_operator_can_start_and_complete() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    // Owner deposits + authorizes operator
    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::authorize_operator(&mut line, OPERATOR, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 101, 100, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 102, 50, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 50);
    test_scenario::return_shared(line);

    // Operator starts production
    scenario.next_tx(OPERATOR);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 1);

    // Operator completes
    clk.set_for_testing(1000 + 60_000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 0);
    assert!(production_line::jobs_completed(&line) == 1);

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

// ─── Start with BPC efficiency ───

#[test]
fun test_start_production_with_efficiency() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 10, scenario.ctx());
    let mut bpc = blueprint::mint_bpc(&mut bpo, 2, scenario.ctx());

    // Deposit materials (ME=10 → actual = ceil(100*90/100) = 90 for ore, ceil(50*90/100) = 45 for crystal)
    production_line::deposit_materials(&mut line, &r, 101, 90, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 102, 45, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 50);

    let (_, me, te) = blueprint::use_bpc(&mut bpc);
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production_with_efficiency(&mut line, &r, me, te, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 1);

    // TE=10 → duration = ceil(60000*90/100) = 54000
    clk.set_for_testing(1000 + 54_000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    assert!(production_line::output_buffer_qty(&line, 201) == 1);

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    destroy(bpc);
    clk.destroy_for_testing();
    scenario.end();
}

// ─── Revoke Operator ───

#[test]
fun test_revoke_operator() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = make_test_recipe(ctx);
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Line A".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::authorize_operator(&mut line, OPERATOR, scenario.ctx());
    production_line::revoke_operator(&mut line, OPERATOR, scenario.ctx());
    test_scenario::return_shared(line);
    destroy(r);
    scenario.end();
}

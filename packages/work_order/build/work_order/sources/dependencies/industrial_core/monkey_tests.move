#[test_only]
module industrial_core::monkey_tests;

use sui::clock;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use industrial_core::production_line;
use industrial_core::trigger_engine;
use std::unit_test::destroy;

const OWNER: address = @0xA;
const OPERATOR: address = @0xB;
const STRANGER: address = @0xC;

// ═══════════════════════════════════════════════════════════════
// RECIPE — Boundary Values
// ═══════════════════════════════════════════════════════════════

/// MAX_U64 quantities should work for recipe creation (no overflow in create)
#[test]
fun monkey_recipe_max_u64_quantities() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Max Recipe".to_string(),
        vector[recipe::new_material_req(1, 18446744073709551615)], // MAX_U64
        recipe::new_material_output(2, 18446744073709551615),
        18446744073709551615,
        18446744073709551615,
        &mut ctx,
    );
    assert!(recipe::base_duration_ms(&r) == 18446744073709551615);
    assert!(recipe::energy_cost(&r) == 18446744073709551615);
    destroy(r);
}

/// Quantity = 1 is the minimum valid value for inputs and output
#[test]
fun monkey_recipe_minimum_valid_quantities() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Min Recipe".to_string(),
        vector[recipe::new_material_req(0, 1)],
        recipe::new_material_output(0, 1),
        1,
        1,
        &mut ctx,
    );
    assert!(recipe::base_duration_ms(&r) == 1);
    destroy(r);
}

/// Many inputs — stress test the input vector validation loop
#[test]
fun monkey_recipe_many_inputs() {
    let mut ctx = tx_context::dummy();
    let mut inputs = vector[];
    let mut i: u32 = 0;
    while (i < 100) {
        inputs.push_back(recipe::new_material_req(i, 1));
        i = i + 1;
    };
    let r = recipe::create_recipe(
        b"Massive Recipe".to_string(),
        inputs,
        recipe::new_material_output(999, 1),
        1000,
        1,
        &mut ctx,
    );
    assert!(recipe::inputs(&r).length() == 100);
    destroy(r);
}

/// Zero quantity in second input should still be caught
#[test]
#[expected_failure(abort_code = recipe::E_RECIPE_ZERO_QUANTITY)]
fun monkey_recipe_zero_qty_in_middle_input() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[
            recipe::new_material_req(1, 10),
            recipe::new_material_req(2, 0),  // zero in 2nd position
            recipe::new_material_req(3, 5),
        ],
        recipe::new_material_output(99, 1),
        1000,
        1,
        &mut ctx,
    );
    destroy(r);
}

/// has_input_type with item_type_id = 0 (boundary)
#[test]
fun monkey_recipe_has_input_type_zero_id() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Zero ID".to_string(),
        vector[recipe::new_material_req(0, 1)],
        recipe::new_material_output(1, 1),
        1000,
        1,
        &mut ctx,
    );
    assert!(recipe::has_input_type(&r, 0) == true);
    assert!(recipe::has_input_type(&r, 1) == false);
    assert!(recipe::has_input_type(&r, 4294967295) == false); // MAX_U32
    destroy(r);
}

// ═══════════════════════════════════════════════════════════════
// BLUEPRINT — Boundary & Repeated Operations
// ═══════════════════════════════════════════════════════════════

/// ME=25, TE=25 is valid (boundary)
#[test]
fun monkey_blueprint_max_valid_efficiency() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 1)],
        recipe::new_material_output(2, 1),
        1000, 1, &mut ctx,
    );
    let bpo = blueprint::mint_bpo(&r, 0, 25, 25, &mut ctx);
    assert!(blueprint::bpo_material_efficiency(&bpo) == 25);
    assert!(blueprint::bpo_time_efficiency(&bpo) == 25);
    destroy(r);
    destroy(bpo);
}

/// ME=255 (max u8) should fail
#[test]
#[expected_failure(abort_code = blueprint::E_EFFICIENCY_OUT_OF_RANGE)]
fun monkey_blueprint_me_max_u8() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 1)],
        recipe::new_material_output(2, 1),
        1000, 1, &mut ctx,
    );
    let bpo = blueprint::mint_bpo(&r, 0, 255, 0, &mut ctx);
    destroy(r);
    destroy(bpo);
}

/// BPC with uses = 0 means it's immediately empty — use_bpc should fail
#[test]
#[expected_failure(abort_code = blueprint::E_BLUEPRINT_NO_USES_LEFT)]
fun monkey_blueprint_bpc_zero_uses_immediate_fail() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 1)],
        recipe::new_material_output(2, 1),
        1000, 1, &mut ctx,
    );
    let mut bpo = blueprint::mint_bpo(&r, 0, 0, 0, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 0, &mut ctx); // 0 uses
    let (_, _, _) = blueprint::use_bpc(&mut bpc); // should fail
    destroy(r);
    destroy(bpo);
    destroy(bpc);
}

/// Mint BPCs up to exactly max_copies, then fail on next
#[test]
#[expected_failure(abort_code = blueprint::E_BLUEPRINT_MAX_COPIES_REACHED)]
fun monkey_blueprint_exact_max_then_overflow() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 1)],
        recipe::new_material_output(2, 1),
        1000, 1, &mut ctx,
    );
    let mut bpo = blueprint::mint_bpo(&r, 3, 0, 0, &mut ctx);
    let bpc1 = blueprint::mint_bpc(&mut bpo, 1, &mut ctx);
    let bpc2 = blueprint::mint_bpc(&mut bpo, 1, &mut ctx);
    let bpc3 = blueprint::mint_bpc(&mut bpo, 1, &mut ctx);
    assert!(blueprint::bpo_copies_minted(&bpo) == 3);
    let bpc4 = blueprint::mint_bpc(&mut bpo, 1, &mut ctx); // should fail
    destroy(r);
    destroy(bpo);
    destroy(bpc1);
    destroy(bpc2);
    destroy(bpc3);
    destroy(bpc4);
}

/// Drain all BPC uses then destroy — full lifecycle
#[test]
fun monkey_blueprint_drain_bpc_then_destroy() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 1)],
        recipe::new_material_output(2, 1),
        1000, 1, &mut ctx,
    );
    let mut bpo = blueprint::mint_bpo(&r, 0, 5, 5, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 100, &mut ctx);
    let mut i = 0;
    while (i < 100) {
        let (_, _, _) = blueprint::use_bpc(&mut bpc);
        i = i + 1;
    };
    assert!(blueprint::bpc_uses_remaining(&bpc) == 0);
    blueprint::destroy_empty_bpc(bpc);
    destroy(r);
    destroy(bpo);
}

/// MAX_U64 uses — BPC can be created with huge uses count
#[test]
fun monkey_blueprint_bpc_max_u64_uses() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 1)],
        recipe::new_material_output(2, 1),
        1000, 1, &mut ctx,
    );
    let mut bpo = blueprint::mint_bpo(&r, 0, 0, 0, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 18446744073709551615, &mut ctx);
    let (_, _, _) = blueprint::use_bpc(&mut bpc);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 18446744073709551614);
    destroy(r);
    destroy(bpo);
    destroy(bpc);
}

// ═══════════════════════════════════════════════════════════════
// PRODUCTION LINE — State Conflicts & Auth Attacks
// ═══════════════════════════════════════════════════════════════

/// Stranger cannot deposit materials
#[test]
#[expected_failure(abort_code = production_line::E_NOT_OWNER)]
fun monkey_prodline_stranger_deposit_materials() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(STRANGER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 1, 10, scenario.ctx());
    test_scenario::return_shared(line);
    destroy(r);
    scenario.end();
}

/// Stranger cannot deposit fuel
#[test]
#[expected_failure(abort_code = production_line::E_NOT_OWNER)]
fun monkey_prodline_stranger_deposit_fuel() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(STRANGER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_fuel(&mut line, 100, scenario.ctx());
    test_scenario::return_shared(line);
    destroy(r);
    scenario.end();
}

/// Stranger cannot start production (not owner, not operator)
#[test]
#[expected_failure(abort_code = production_line::E_NOT_AUTHORIZED_OPERATOR)]
fun monkey_prodline_stranger_start_production() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 10);
    test_scenario::return_shared(line);

    scenario.next_tx(STRANGER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let clk = clock::create_for_testing(scenario.ctx());
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Double start — line already RUNNING, start again should fail
#[test]
#[expected_failure(abort_code = production_line::E_PRODUCTION_LINE_BUSY)]
fun monkey_prodline_double_start() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 20, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 20);

    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    // Try starting again while RUNNING
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Complete on IDLE line (status != RUNNING) should fail with E_PRODUCTION_LINE_BUSY
#[test]
#[expected_failure(abort_code = production_line::E_PRODUCTION_LINE_BUSY)]
fun monkey_prodline_complete_when_idle() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let clk = clock::create_for_testing(scenario.ctx());
    production_line::complete_production(&mut line, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    destroy(r);
    clk.destroy_for_testing();
    scenario.end();
}

/// Withdraw more than available output
#[test]
#[expected_failure(abort_code = production_line::E_INSUFFICIENT_OUTPUT)]
fun monkey_prodline_withdraw_more_than_available() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    // Output buffer is empty, try to withdraw
    production_line::withdraw_output(&mut line, 2, 1, scenario.ctx());

    test_scenario::return_shared(line);
    destroy(r);
    scenario.end();
}

/// Wrong recipe blueprint — BPO for recipe A, line for recipe B
#[test]
#[expected_failure(abort_code = production_line::E_RECIPE_BLUEPRINT_MISMATCH)]
fun monkey_prodline_wrong_blueprint_recipe() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r1 = recipe::create_recipe(
        b"R1".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let r2 = recipe::create_recipe(
        b"R2".to_string(),
        vector[recipe::new_material_req(3, 5)],
        recipe::new_material_output(4, 1),
        2000, 20, ctx,
    );
    let recipe_id1 = object::id(&r1);
    production_line::create_production_line(b"L".to_string(), recipe_id1, ctx);
    // BPO is for r2, not r1
    let bpo = blueprint::mint_bpo(&r2, 0, 0, 0, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r1, 1, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 10);

    let clk = clock::create_for_testing(scenario.ctx());
    // BPO recipe_id != line recipe_id
    production_line::start_production(&mut line, &r1, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    destroy(r1);
    destroy(r2);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Complete at exactly job_end - 1 ms should fail (off-by-one)
#[test]
#[expected_failure(abort_code = production_line::E_PRODUCTION_NOT_COMPLETE)]
fun monkey_prodline_complete_one_ms_early() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        10_000, 5, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 5);

    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    // job_end = 1000 + 10000 = 11000, try completing at 10999
    clk.set_for_testing(10999);
    production_line::complete_production(&mut line, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Revoked operator cannot start production
#[test]
#[expected_failure(abort_code = production_line::E_NOT_AUTHORIZED_OPERATOR)]
fun monkey_prodline_revoked_operator_starts() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::authorize_operator(&mut line, OPERATOR, scenario.ctx());
    production_line::revoke_operator(&mut line, OPERATOR, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 10);
    test_scenario::return_shared(line);

    scenario.next_tx(OPERATOR);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let clk = clock::create_for_testing(scenario.ctx());
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Deposit zero quantity material (should succeed — no validation on qty in deposit)
/// Verifies it doesn't break the buffer
#[test]
fun monkey_prodline_deposit_zero_quantity() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 1),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 1, 0, scenario.ctx());
    assert!(production_line::input_buffer_qty(&line, 1) == 0);
    test_scenario::return_shared(line);
    destroy(r);
    scenario.end();
}

// ═══════════════════════════════════════════════════════════════
// TRIGGER ENGINE — Cooldown Boundaries & State Conflicts
// ═══════════════════════════════════════════════════════════════

/// Execute trigger while line is RUNNING should fail (start_production checks idle)
#[test]
#[expected_failure(abort_code = production_line::E_PRODUCTION_LINE_BUSY)]
fun monkey_trigger_execute_on_busy_line() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 5),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 20, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 20);

    trigger_engine::create_trigger_rule(&line, 0, 10, 2, true, 0, scenario.ctx());
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    // First trigger starts production
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 1);
    // Second trigger on busy line
    clk.set_for_testing(1001);
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Execute disabled trigger should fail
#[test]
#[expected_failure(abort_code = trigger_engine::E_TRIGGER_DISABLED)]
fun monkey_trigger_execute_disabled() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 5),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 10);
    trigger_engine::create_trigger_rule(&line, 0, 10, 2, true, 0, scenario.ctx());
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    trigger_engine::toggle_trigger(&mut rule, false);
    let clk = clock::create_for_testing(scenario.ctx());
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Execute trigger during cooldown should fail
#[test]
#[expected_failure(abort_code = trigger_engine::E_TRIGGER_COOLDOWN)]
fun monkey_trigger_execute_during_cooldown() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 5),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 20, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 20);
    trigger_engine::create_trigger_rule(&line, 0, 100, 2, true, 60_000, scenario.ctx());
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    // First execute succeeds
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());
    // Complete production so line is idle
    clk.set_for_testing(1000 + 1000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    // Try again at 2001 — within 60s cooldown (last_triggered=1000, cooldown=60000)
    clk.set_for_testing(2001);
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Trigger with condition not met (output above threshold) should fail
#[test]
#[expected_failure(abort_code = trigger_engine::E_TRIGGER_CONDITION_NOT_MET)]
fun monkey_trigger_condition_not_met() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 5),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    // Produce first to fill output buffer
    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 20, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 20);

    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    clk.set_for_testing(2000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    // Output buffer: item 2 = 5

    // Create trigger with threshold = 3 (output 5 >= 3, condition NOT met)
    trigger_engine::create_trigger_rule(&line, 0, 3, 2, true, 0, scenario.ctx());
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    clk.set_for_testing(3000);
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Trigger with auto_repeat=false should disable after first execution
#[test]
fun monkey_trigger_auto_repeat_false_disables() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 5),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 10);
    trigger_engine::create_trigger_rule(&line, 0, 10, 2, false, 0, scenario.ctx());
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());
    // After execute, auto_repeat=false → rule.enabled should be false
    assert!(trigger_engine::rule_enabled(&rule) == false);
    // evaluate should return false now
    assert!(trigger_engine::evaluate_trigger(&rule, &line, &clk) == false);

    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Cooldown boundary: execute at exactly cooldown expiry should succeed
#[test]
fun monkey_trigger_cooldown_exact_boundary() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 5),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 20, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 20);
    trigger_engine::create_trigger_rule(&line, 0, 100, 2, true, 5000, scenario.ctx());
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());
    // Complete production
    clk.set_for_testing(2000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    // Cooldown expires at 1000 + 5000 = 6000. Execute at exactly 6000
    clk.set_for_testing(6000);
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 1);

    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Unknown condition_type (e.g., 99) — evaluate should return false
#[test]
fun monkey_trigger_unknown_condition_type() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 5),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    // condition_type = 99 (unsupported)
    trigger_engine::create_trigger_rule(&line, 99, 10, 2, true, 0, scenario.ctx());
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    let rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let clk = clock::create_for_testing(scenario.ctx());
    // Should return false — unknown condition always fails
    assert!(trigger_engine::evaluate_trigger(&rule, &line, &clk) == false);
    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    clk.destroy_for_testing();
    scenario.end();
}

/// Execute trigger with unknown condition should fail (condition not met)
#[test]
#[expected_failure(abort_code = trigger_engine::E_TRIGGER_CONDITION_NOT_MET)]
fun monkey_trigger_execute_unknown_condition() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R".to_string(),
        vector[recipe::new_material_req(1, 10)],
        recipe::new_material_output(2, 5),
        1000, 10, ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"L".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    production_line::deposit_materials(&mut line, &r, 1, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 10);
    trigger_engine::create_trigger_rule(&line, 99, 10, 2, true, 0, scenario.ctx());
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let clk = clock::create_for_testing(scenario.ctx());
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

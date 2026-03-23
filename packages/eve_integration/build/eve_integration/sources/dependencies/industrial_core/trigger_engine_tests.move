#[test_only]
module industrial_core::trigger_engine_tests;

use sui::clock;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use industrial_core::production_line;
use industrial_core::trigger_engine;
use std::unit_test::destroy;

const OWNER: address = @0xA;
const STRANGER: address = @0xC;

fun setup_line_with_materials(scenario: &mut test_scenario::Scenario): recipe::Recipe {
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"Ammo".to_string(),
        vector[recipe::new_material_req(101, 10)],
        recipe::new_material_output(301, 5),
        30_000,
        20,
        ctx,
    );
    let recipe_id = object::id(&r);
    production_line::create_production_line(b"Ammo Line".to_string(), recipe_id, ctx);
    r
}

// ─── Create Trigger ───

#[test]
fun test_create_trigger_rule_by_owner() {
    let mut scenario = test_scenario::begin(OWNER);
    let r = setup_line_with_materials(&mut scenario);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    trigger_engine::create_trigger_rule(
        &line,
        0,     // inventory_below
        10,    // threshold
        301,   // target output item
        true,  // auto_repeat
        5000,  // cooldown 5s
        scenario.ctx(),
    );
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    assert!(trigger_engine::rule_enabled(&rule) == true);
    assert!(trigger_engine::rule_threshold(&rule) == 10);
    scenario.return_to_sender(rule);
    destroy(r);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = trigger_engine::E_NOT_OWNER)]
fun test_create_trigger_rule_by_non_owner() {
    let mut scenario = test_scenario::begin(OWNER);
    let r = setup_line_with_materials(&mut scenario);

    scenario.next_tx(STRANGER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    trigger_engine::create_trigger_rule(
        &line, 0, 10, 301, true, 5000, scenario.ctx(),
    );
    test_scenario::return_shared(line);
    destroy(r);
    scenario.end();
}

// ─── Evaluate Trigger ───

#[test]
fun test_evaluate_inventory_below_threshold() {
    let mut scenario = test_scenario::begin(OWNER);
    let r = setup_line_with_materials(&mut scenario);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    trigger_engine::create_trigger_rule(
        &line, 0, 10, 301, true, 0, scenario.ctx(),
    );
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    let rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let clk = clock::create_for_testing(scenario.ctx());
    // Output buffer empty → 0 < 10 threshold → true
    assert!(trigger_engine::evaluate_trigger(&rule, &line, &clk) == true);
    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    clk.destroy_for_testing();
    destroy(r);
    scenario.end();
}

#[test]
fun test_evaluate_inventory_above_threshold() {
    let mut scenario = test_scenario::begin(OWNER);
    let r = setup_line_with_materials(&mut scenario);

    // Deposit + produce to fill output buffer
    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 101, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 20);
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    clk.set_for_testing(1000 + 30_000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    // Output buffer now has 301 x 5

    trigger_engine::create_trigger_rule(
        &line, 0, 3, 301, true, 0, scenario.ctx(), // threshold=3, have 5
    );
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    let rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    // 5 >= 3 → false
    assert!(trigger_engine::evaluate_trigger(&rule, &line, &clk) == false);
    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_evaluate_disabled_rule() {
    let mut scenario = test_scenario::begin(OWNER);
    let r = setup_line_with_materials(&mut scenario);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    trigger_engine::create_trigger_rule(
        &line, 0, 10, 301, true, 0, scenario.ctx(),
    );
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    trigger_engine::toggle_trigger(&mut rule, false);
    let clk = clock::create_for_testing(scenario.ctx());
    assert!(trigger_engine::evaluate_trigger(&rule, &line, &clk) == false);
    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    clk.destroy_for_testing();
    destroy(r);
    scenario.end();
}

#[test]
fun test_evaluate_cooldown_active() {
    let mut scenario = test_scenario::begin(OWNER);
    let r = setup_line_with_materials(&mut scenario);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    trigger_engine::create_trigger_rule(
        &line, 0, 10, 301, true, 10_000, scenario.ctx(), // 10s cooldown
    );
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    // Simulate last_triggered = 5000, clock = 8000 → within cooldown
    trigger_engine::set_last_triggered_for_testing(&mut rule, 5000);
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(8000); // 8000 < 5000 + 10000
    assert!(trigger_engine::evaluate_trigger(&rule, &line, &clk) == false);
    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    clk.destroy_for_testing();
    destroy(r);
    scenario.end();
}

// ─── Execute Trigger ───

#[test]
fun test_execute_trigger_success() {
    let mut scenario = test_scenario::begin(OWNER);
    let r = setup_line_with_materials(&mut scenario);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 101, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 20);
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, scenario.ctx());
    trigger_engine::create_trigger_rule(
        &line, 0, 10, 301, true, 0, scenario.ctx(),
    );
    test_scenario::return_shared(line);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 1); // RUNNING
    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = trigger_engine::E_TRIGGER_LINE_MISMATCH)]
fun test_execute_trigger_line_mismatch() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let r = recipe::create_recipe(
        b"R1".to_string(),
        vector[recipe::new_material_req(101, 10)],
        recipe::new_material_output(301, 5),
        30_000, 20, ctx,
    );
    let r2 = recipe::create_recipe(
        b"R2".to_string(),
        vector[recipe::new_material_req(102, 10)],
        recipe::new_material_output(302, 5),
        30_000, 20, ctx,
    );
    let recipe_id1 = object::id(&r);
    let recipe_id2 = object::id(&r2);
    production_line::create_production_line(b"Line1".to_string(), recipe_id1, ctx);
    production_line::create_production_line(b"Line2".to_string(), recipe_id2, ctx);

    // Create rule on Line1
    scenario.next_tx(OWNER);
    let line1 = scenario.take_shared<production_line::ProductionLine>();
    trigger_engine::create_trigger_rule(
        &line1, 0, 10, 301, true, 0, scenario.ctx(),
    );
    test_scenario::return_shared(line1);

    // Try to execute on Line2 (mismatch)
    scenario.next_tx(OWNER);
    let line1 = scenario.take_shared<production_line::ProductionLine>();
    let mut line2 = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let bpo = blueprint::mint_bpo(&r2, 0, 0, 0, scenario.ctx());
    let clk = clock::create_for_testing(scenario.ctx());
    trigger_engine::execute_trigger(&mut rule, &mut line2, &r2, &bpo, &clk, scenario.ctx());

    test_scenario::return_shared(line1);
    test_scenario::return_shared(line2);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(r2);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

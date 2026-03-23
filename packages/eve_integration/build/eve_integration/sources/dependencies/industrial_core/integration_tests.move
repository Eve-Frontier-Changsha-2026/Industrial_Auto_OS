#[test_only]
module industrial_core::integration_tests;

use sui::clock;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use industrial_core::production_line;
use industrial_core::trigger_engine;
use std::unit_test::destroy;

const OWNER: address = @0xA;

/// Full production cycle:
/// Recipe → BPO → Line → Deposit → Produce → Complete → Withdraw
#[test]
fun test_full_production_cycle() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();

    // 1. Create recipe (ore x100 → hull x1, 60s, energy=50)
    let r = recipe::create_recipe(
        b"Frigate Hull".to_string(),
        vector[recipe::new_material_req(101, 100)],
        recipe::new_material_output(201, 1),
        60_000,
        50,
        ctx,
    );
    let recipe_id = object::id(&r);

    // 2. Mint BPO (ME=10, TE=10)
    let bpo = blueprint::mint_bpo(&r, 0, 10, 10, ctx);

    // 3. Create production line
    production_line::create_production_line(b"Hull Factory".to_string(), recipe_id, ctx);

    // 4-5. Deposit materials + fuel
    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    // ME=10 → actual ore = ceil(100*90/100) = 90
    production_line::deposit_materials(&mut line, &r, 101, 90, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 50);

    // 6. Start production
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(10_000);
    production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 1); // RUNNING
    assert!(production_line::input_buffer_qty(&line, 101) == 0); // all consumed

    // 7-8. Advance clock + complete
    // TE=10 → actual_duration = ceil(60000*90/100) = 54000
    clk.set_for_testing(10_000 + 54_000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 0); // IDLE
    assert!(production_line::jobs_completed(&line) == 1);

    // 9. Assert output
    assert!(production_line::output_buffer_qty(&line, 201) == 1);

    // 10. Withdraw
    production_line::withdraw_output(&mut line, 201, 1, scenario.ctx());
    assert!(production_line::output_buffer_qty(&line, 201) == 0);

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Trigger auto-production:
/// Setup → Create trigger → Evaluate (true) → Execute → Line running
#[test]
fun test_trigger_auto_production() {
    let mut scenario = test_scenario::begin(OWNER);
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
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, ctx);
    production_line::create_production_line(b"Ammo Line".to_string(), recipe_id, ctx);

    // Deposit materials + fuel + create trigger
    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 101, 10, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 20);
    trigger_engine::create_trigger_rule(
        &line,
        0,     // inventory_below
        10,    // threshold=10 for output item 301
        301,
        true,
        0,     // no cooldown
        scenario.ctx(),
    );
    test_scenario::return_shared(line);

    // Evaluate + execute trigger
    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    let mut rule = scenario.take_from_sender<trigger_engine::TriggerRule>();
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(5000);

    // Evaluate: output buffer has 0 items of 301, threshold = 10 → true
    assert!(trigger_engine::evaluate_trigger(&rule, &line, &clk) == true);

    // Execute: starts production
    trigger_engine::execute_trigger(&mut rule, &mut line, &r, &bpo, &clk, scenario.ctx());
    assert!(production_line::status(&line) == 1); // RUNNING

    // Complete production
    clk.set_for_testing(5000 + 30_000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    assert!(production_line::output_buffer_qty(&line, 301) == 5);
    assert!(production_line::status(&line) == 0); // IDLE

    // Re-evaluate: now has 5 items, still < 10 → true again (auto_repeat)
    assert!(trigger_engine::evaluate_trigger(&rule, &line, &clk) == true);

    test_scenario::return_shared(line);
    scenario.return_to_sender(rule);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// BPC production flow:
/// mint_bpc → use_bpc → start_production_with_efficiency → complete → repeat → destroy
#[test]
fun test_bpc_production_flow() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();

    let r = recipe::create_recipe(
        b"Missiles".to_string(),
        vector[recipe::new_material_req(101, 20)],
        recipe::new_material_output(401, 10),
        20_000,
        15,
        ctx,
    );
    let recipe_id = object::id(&r);
    let mut bpo = blueprint::mint_bpo(&r, 0, 15, 20, ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 2, ctx);
    production_line::create_production_line(b"Missile Line".to_string(), recipe_id, ctx);

    // Deposit enough materials for 2 runs
    // ME=15 → actual = ceil(20*85/100) = ceil(17) = 17 per run → 34 total
    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 101, 34, scenario.ctx());
    production_line::add_fuel_internal(&mut line, 30); // 15 per run

    // Run 1: use BPC
    let (_, me, te) = blueprint::use_bpc(&mut bpc);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 1);
    let mut clk = clock::create_for_testing(scenario.ctx());
    clk.set_for_testing(1000);
    production_line::start_production_with_efficiency(&mut line, &r, me, te, &clk, scenario.ctx());

    // TE=20 → duration = ceil(20000*80/100) = 16000
    clk.set_for_testing(1000 + 16_000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    assert!(production_line::output_buffer_qty(&line, 401) == 10);
    assert!(production_line::jobs_completed(&line) == 1);

    // Run 2: use BPC again
    let (_, me2, te2) = blueprint::use_bpc(&mut bpc);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 0);
    clk.set_for_testing(20_000);
    production_line::start_production_with_efficiency(&mut line, &r, me2, te2, &clk, scenario.ctx());
    clk.set_for_testing(20_000 + 16_000);
    production_line::complete_production(&mut line, &clk, scenario.ctx());
    assert!(production_line::output_buffer_qty(&line, 401) == 20);
    assert!(production_line::jobs_completed(&line) == 2);

    // Destroy empty BPC
    blueprint::destroy_empty_bpc(bpc);

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

/// Multiple production runs accumulate output
#[test]
fun test_multiple_production_runs() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();

    let r = recipe::create_recipe(
        b"Bolts".to_string(),
        vector[recipe::new_material_req(101, 5)],
        recipe::new_material_output(501, 100),
        5_000,
        5,
        ctx,
    );
    let recipe_id = object::id(&r);
    let bpo = blueprint::mint_bpo(&r, 0, 0, 0, ctx);
    production_line::create_production_line(b"Bolt Line".to_string(), recipe_id, ctx);

    scenario.next_tx(OWNER);
    let mut line = scenario.take_shared<production_line::ProductionLine>();
    production_line::deposit_materials(&mut line, &r, 101, 15, scenario.ctx()); // enough for 3 runs
    production_line::add_fuel_internal(&mut line, 15);

    let mut clk = clock::create_for_testing(scenario.ctx());
    let mut t: u64 = 1000;

    // Run 3 production cycles
    let mut run = 0;
    while (run < 3) {
        clk.set_for_testing(t);
        production_line::start_production(&mut line, &r, &bpo, &clk, scenario.ctx());
        t = t + 5_000;
        clk.set_for_testing(t);
        production_line::complete_production(&mut line, &clk, scenario.ctx());
        run = run + 1;
    };

    assert!(production_line::output_buffer_qty(&line, 501) == 300);
    assert!(production_line::jobs_completed(&line) == 3);

    test_scenario::return_shared(line);
    destroy(r);
    destroy(bpo);
    clk.destroy_for_testing();
    scenario.end();
}

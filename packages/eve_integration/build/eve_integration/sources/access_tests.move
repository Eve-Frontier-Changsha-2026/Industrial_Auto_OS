#[test_only]
module eve_integration::access_tests;

use std::string;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use industrial_core::production_line;
use eve_integration::factory_access::{Self, AccessRegistry, AccessPass};

#[test]
fun test_claim_from_blueprint_happy_path() {
    let mut scenario = test_scenario::begin(@0xAA);
    {
        factory_access::init_for_testing(scenario.ctx());
    };
    // Create recipe and production line
    scenario.next_tx(@0xAA);
    {
        let inputs = vector[recipe::new_material_req(1001, 10)];
        let output = recipe::new_material_output(2001, 1);
        let r = recipe::create_recipe(
            string::utf8(b"TestRecipe"),
            inputs,
            output,
            60000,
            100,
            scenario.ctx(),
        );
        let recipe_id = recipe::recipe_id(&r);
        // Create production line with this recipe
        production_line::create_production_line(
            string::utf8(b"TestLine"),
            recipe_id,
            scenario.ctx(),
        );
        // Mint BPO from recipe
        let bpo = blueprint::mint_bpo(&r, 0, 10, 5, scenario.ctx());
        transfer::public_transfer(bpo, @0xAA);
        transfer::public_transfer(r, @0xAA);
    };
    // Claim access pass from blueprint
    scenario.next_tx(@0xAA);
    {
        let mut access_registry = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        factory_access::claim_from_blueprint(
            &mut access_registry,
            &bpo,
            &line,
            scenario.ctx(),
        );

        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_registry);
    };
    // Verify pass was created
    scenario.next_tx(@0xAA);
    {
        assert!(test_scenario::has_most_recent_for_address<AccessPass>(@0xAA));
        let pass = scenario.take_from_sender<AccessPass>();
        assert!(factory_access::pass_holder(&pass) == @0xAA);
        assert!(factory_access::pass_type(&pass) == 0); // PASS_TYPE_BLUEPRINT
        assert!(factory_access::pass_expires_at(&pass).is_none());
        scenario.return_to_sender(pass);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = factory_access::E_RECIPE_MISMATCH)]
fun test_claim_from_blueprint_recipe_mismatch() {
    let mut scenario = test_scenario::begin(@0xAA);
    {
        factory_access::init_for_testing(scenario.ctx());
    };
    // Create two different recipes
    scenario.next_tx(@0xAA);
    {
        let inputs_a = vector[recipe::new_material_req(1001, 10)];
        let output_a = recipe::new_material_output(2001, 1);
        let recipe_a = recipe::create_recipe(
            string::utf8(b"RecipeA"),
            inputs_a,
            output_a,
            60000,
            100,
            scenario.ctx(),
        );

        let inputs_b = vector[recipe::new_material_req(1002, 5)];
        let output_b = recipe::new_material_output(2002, 1);
        let recipe_b = recipe::create_recipe(
            string::utf8(b"RecipeB"),
            inputs_b,
            output_b,
            30000,
            50,
            scenario.ctx(),
        );

        // BPO from recipe_a, line from recipe_b
        let bpo = blueprint::mint_bpo(&recipe_a, 0, 10, 5, scenario.ctx());
        let recipe_b_id = recipe::recipe_id(&recipe_b);
        production_line::create_production_line(
            string::utf8(b"LineB"),
            recipe_b_id,
            scenario.ctx(),
        );

        transfer::public_transfer(bpo, @0xAA);
        transfer::public_transfer(recipe_a, @0xAA);
        transfer::public_transfer(recipe_b, @0xAA);
    };
    // Attempt claim with mismatched recipe — should fail
    scenario.next_tx(@0xAA);
    {
        let mut access_registry = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        factory_access::claim_from_blueprint(
            &mut access_registry,
            &bpo,
            &line,
            scenario.ctx(),
        );

        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_registry);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = factory_access::E_DUPLICATE_PASS)]
fun test_duplicate_claim_fails() {
    let mut scenario = test_scenario::begin(@0xAA);
    {
        factory_access::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAA);
    {
        let inputs = vector[recipe::new_material_req(1001, 10)];
        let output = recipe::new_material_output(2001, 1);
        let r = recipe::create_recipe(
            string::utf8(b"TestRecipe"),
            inputs,
            output,
            60000,
            100,
            scenario.ctx(),
        );
        let recipe_id = recipe::recipe_id(&r);
        production_line::create_production_line(
            string::utf8(b"TestLine"),
            recipe_id,
            scenario.ctx(),
        );
        let bpo = blueprint::mint_bpo(&r, 0, 10, 5, scenario.ctx());
        transfer::public_transfer(bpo, @0xAA);
        transfer::public_transfer(r, @0xAA);
    };
    // First claim — succeeds
    scenario.next_tx(@0xAA);
    {
        let mut access_registry = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        factory_access::claim_from_blueprint(
            &mut access_registry,
            &bpo,
            &line,
            scenario.ctx(),
        );

        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_registry);
    };
    // Second claim — should fail with E_DUPLICATE_PASS
    scenario.next_tx(@0xAA);
    {
        let mut access_registry = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        factory_access::claim_from_blueprint(
            &mut access_registry,
            &bpo,
            &line,
            scenario.ctx(),
        );

        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_registry);
    };
    scenario.end();
}

#[test]
fun test_admin_revoke_blocks_permit() {
    let mut scenario = test_scenario::begin(@0xAA);
    {
        factory_access::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAA);
    {
        let inputs = vector[recipe::new_material_req(1001, 10)];
        let output = recipe::new_material_output(2001, 1);
        let r = recipe::create_recipe(
            string::utf8(b"TestRecipe"),
            inputs,
            output,
            60000,
            100,
            scenario.ctx(),
        );
        let recipe_id = recipe::recipe_id(&r);
        production_line::create_production_line(
            string::utf8(b"TestLine"),
            recipe_id,
            scenario.ctx(),
        );
        let bpo = blueprint::mint_bpo(&r, 0, 10, 5, scenario.ctx());
        transfer::public_transfer(bpo, @0xAA);
        transfer::public_transfer(r, @0xAA);
    };
    // Claim pass
    scenario.next_tx(@0xAA);
    {
        let mut access_registry = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        factory_access::claim_from_blueprint(
            &mut access_registry,
            &bpo,
            &line,
            scenario.ctx(),
        );

        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_registry);
    };
    // Admin revoke
    scenario.next_tx(@0xAA);
    {
        let mut access_registry = scenario.take_shared<AccessRegistry>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
        let pass = scenario.take_from_sender<AccessPass>();
        let pass_id = object::id(&pass);

        factory_access::admin_revoke_pass(
            &mut access_registry,
            pass_id,
            @0xAA,
            &line,
            scenario.ctx(),
        );

        // Verify pass is revoked
        assert!(factory_access::is_pass_revoked(&access_registry, pass_id));

        scenario.return_to_sender(pass);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_registry);
    };
    scenario.end();
}

#[test]
fun test_surrender_pass() {
    let mut scenario = test_scenario::begin(@0xAA);
    {
        factory_access::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAA);
    {
        let inputs = vector[recipe::new_material_req(1001, 10)];
        let output = recipe::new_material_output(2001, 1);
        let r = recipe::create_recipe(
            string::utf8(b"TestRecipe"),
            inputs,
            output,
            60000,
            100,
            scenario.ctx(),
        );
        let recipe_id = recipe::recipe_id(&r);
        production_line::create_production_line(
            string::utf8(b"TestLine"),
            recipe_id,
            scenario.ctx(),
        );
        let bpo = blueprint::mint_bpo(&r, 0, 10, 5, scenario.ctx());
        transfer::public_transfer(bpo, @0xAA);
        transfer::public_transfer(r, @0xAA);
    };
    // Claim pass
    scenario.next_tx(@0xAA);
    {
        let mut access_registry = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        factory_access::claim_from_blueprint(
            &mut access_registry,
            &bpo,
            &line,
            scenario.ctx(),
        );

        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_registry);
    };
    // Surrender pass
    scenario.next_tx(@0xAA);
    {
        let mut access_registry = scenario.take_shared<AccessRegistry>();
        let pass = scenario.take_from_sender<AccessPass>();

        factory_access::surrender_pass(
            &mut access_registry,
            pass,
            scenario.ctx(),
        );

        test_scenario::return_shared(access_registry);
    };
    // Verify pass is gone
    scenario.next_tx(@0xAA);
    {
        assert!(!test_scenario::has_most_recent_for_address<AccessPass>(@0xAA));
    };
    scenario.end();
}

// === TODO: Lease and WorkOrder claim tests ===
// These require complex cross-package setup (Coin<SUI> minting, Clock, WorkOrderBoard)
// and will be implemented as part of monkey/integration testing.

// TODO: test_claim_from_lease_happy_path
// TODO: test_claim_from_lease_inactive_fails
// TODO: test_claim_from_work_order_happy_path
// TODO: test_claim_from_work_order_wrong_status_fails
// TODO: test_revoke_expired_pass

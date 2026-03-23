#[test_only]
module eve_integration::monkey_tests;

use std::string;
use sui::test_scenario;
use industrial_core::recipe;
use industrial_core::blueprint;
use industrial_core::production_line;
use eve_integration::eve_bridge::{Self, GlobalRegistry, RegistryAdminCap};
use eve_integration::factory_access::{Self, AccessRegistry, AccessPass};

// ============================================================
// Helper: set up common fixtures (bridge registry + access registry + recipe + line + bpo)
// ============================================================

fun setup_bridge(scenario: &mut test_scenario::Scenario) {
    eve_bridge::init_for_testing(scenario.ctx());
}

fun setup_access(scenario: &mut test_scenario::Scenario) {
    factory_access::init_for_testing(scenario.ctx());
}

/// Creates a recipe, production line, and BPO for `owner`.
fun setup_line_and_bpo(scenario: &mut test_scenario::Scenario, owner: address) {
    scenario.next_tx(owner);
    let inputs = vector[recipe::new_material_req(1001, 10)];
    let output = recipe::new_material_output(2001, 1);
    let r = recipe::create_recipe(
        string::utf8(b"MonkeyRecipe"),
        inputs,
        output,
        60000,
        100,
        scenario.ctx(),
    );
    let recipe_id = recipe::recipe_id(&r);
    production_line::create_production_line(
        string::utf8(b"MonkeyLine"),
        recipe_id,
        scenario.ctx(),
    );
    let bpo = blueprint::mint_bpo(&r, 0, 10, 5, scenario.ctx());
    transfer::public_transfer(bpo, owner);
    transfer::public_transfer(r, owner);
}

// ============================================================
// 1. Claim and immediate surrender in same tx block
// ============================================================
#[test]
fun test_claim_and_immediate_surrender() {
    let owner = @0xAA;
    let mut scenario = test_scenario::begin(owner);
    setup_access(&mut scenario);
    setup_line_and_bpo(&mut scenario, owner);

    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());

        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_reg);
    };
    // Surrender in the very next tx (same epoch)
    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let pass = scenario.take_from_sender<AccessPass>();
        factory_access::surrender_pass(&mut access_reg, pass, scenario.ctx());
        test_scenario::return_shared(access_reg);
    };
    // Confirm pass is gone
    scenario.next_tx(owner);
    {
        assert!(!test_scenario::has_most_recent_for_address<AccessPass>(owner));
    };
    scenario.end();
}

// ============================================================
// 2. Add duplicate mapping — should abort E_MAPPING_ALREADY_EXISTS
// ============================================================
#[test]
#[expected_failure(abort_code = eve_bridge::E_MAPPING_ALREADY_EXISTS)]
fun test_add_duplicate_mapping() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    setup_bridge(&mut scenario);

    scenario.next_tx(admin);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        eve_bridge::add_global_mapping(&mut registry, &cap, 42000, string::utf8(b"iron"));
        // Second add with same eve_type_id → boom
        eve_bridge::add_global_mapping(&mut registry, &cap, 42000, string::utf8(b"steel"));

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

// ============================================================
// 3. Enable mapping that was never disabled
//    The factory override key doesn't exist → E_MAPPING_NOT_FOUND
// ============================================================
#[test]
#[expected_failure(abort_code = eve_bridge::E_MAPPING_NOT_FOUND)]
fun test_enable_mapping_that_was_never_disabled() {
    let owner = @0xAA;
    let mut scenario = test_scenario::begin(owner);
    setup_bridge(&mut scenario);

    // Create a production line for factory-level calls
    scenario.next_tx(owner);
    {
        let inputs = vector[recipe::new_material_req(1001, 10)];
        let output = recipe::new_material_output(2001, 1);
        let r = recipe::create_recipe(
            string::utf8(b"R"), inputs, output, 60000, 100, scenario.ctx(),
        );
        let recipe_id = recipe::recipe_id(&r);
        production_line::create_production_line(
            string::utf8(b"L"), recipe_id, scenario.ctx(),
        );
        transfer::public_transfer(r, owner);
    };

    scenario.next_tx(owner);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        eve_bridge::add_global_mapping(&mut registry, &cap, 55555, string::utf8(b"unobtanium"));

        // enable without ever disabling → no FactoryOverrideKey → E_MAPPING_NOT_FOUND
        eve_bridge::enable_factory_mapping(&mut registry, &line, 55555, scenario.ctx());

        scenario.return_to_sender(cap);
        test_scenario::return_shared(line);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

// ============================================================
// 3b. Enable a type that exists in override but was never disabled
//     Override key exists (from disabling another type), but this type is not in disabled_types
//     → VecSet remove aborts with sui::vec_set::EKeyDoesNotExist (1)
// ============================================================
#[test]
#[expected_failure]
fun test_enable_type_not_in_disabled_set() {
    let owner = @0xAA;
    let mut scenario = test_scenario::begin(owner);
    setup_bridge(&mut scenario);

    scenario.next_tx(owner);
    {
        let inputs = vector[recipe::new_material_req(1001, 10)];
        let output = recipe::new_material_output(2001, 1);
        let r = recipe::create_recipe(
            string::utf8(b"R"), inputs, output, 60000, 100, scenario.ctx(),
        );
        let recipe_id = recipe::recipe_id(&r);
        production_line::create_production_line(
            string::utf8(b"L"), recipe_id, scenario.ctx(),
        );
        transfer::public_transfer(r, owner);
    };

    scenario.next_tx(owner);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        // Add two mappings
        eve_bridge::add_global_mapping(&mut registry, &cap, 11111, string::utf8(b"alpha"));
        eve_bridge::add_global_mapping(&mut registry, &cap, 22222, string::utf8(b"beta"));

        // Disable type 11111 → creates FactoryOverrideKey
        let factory_id = object::id(&line);
        eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 11111);

        // Try to enable type 22222 which was never disabled → VecSet::remove aborts
        eve_bridge::enable_factory_mapping(&mut registry, &line, 22222, scenario.ctx());

        scenario.return_to_sender(cap);
        test_scenario::return_shared(line);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

// ============================================================
// 4. Remove global mapping then resolve for factory that had it disabled
// ============================================================
#[test]
fun test_remove_mapping_then_factory_resolve_stale() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    setup_bridge(&mut scenario);

    scenario.next_tx(admin);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));

        let factory_id = object::id_from_address(@0xFA);
        eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 12001);

        // Remove global mapping
        eve_bridge::remove_global_mapping(&mut registry, &cap, 12001);

        // Factory resolve should return none (global gone)
        let result = eve_bridge::resolve_eve_to_industrial_for_factory(&registry, factory_id, 12001);
        assert!(result.is_none());

        // Global resolve also none
        let global = eve_bridge::resolve_eve_to_industrial(&registry, 12001);
        assert!(global.is_none());

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

// ============================================================
// 5. Max mappings stress — 50+ mappings, verify all resolve
// ============================================================
#[test]
fun test_max_mappings_stress() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    setup_bridge(&mut scenario);

    scenario.next_tx(admin);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        // Add 60 mappings
        let mut i: u64 = 0;
        while (i < 60) {
            let eve_id = 100000 + i;
            // Build a unique material name: "mat_XX"
            let mat = if (i < 10) {
                let mut v = b"mat_0";
                v.push_back(48 + (i as u8)); // '0' + i
                string::utf8(v)
            } else {
                let mut v = b"mat_";
                v.push_back(48 + ((i / 10) as u8));
                v.push_back(48 + ((i % 10) as u8));
                string::utf8(v)
            };
            eve_bridge::add_global_mapping(&mut registry, &cap, eve_id, mat);
            i = i + 1;
        };

        // Verify all 60 resolve correctly
        let mut j: u64 = 0;
        while (j < 60) {
            let eve_id = 100000 + j;
            let result = eve_bridge::resolve_eve_to_industrial(&registry, eve_id);
            assert!(result.is_some());
            j = j + 1;
        };

        // Spot-check reverse
        let rev = eve_bridge::resolve_industrial_to_eve(&registry, string::utf8(b"mat_00"));
        assert!(rev.is_some());
        assert!(*rev.borrow() == 100000);

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

// ============================================================
// 6. Factory owner cannot create new mapping — disable_factory_mapping_admin
//    only works on types that already exist in global
// ============================================================
#[test]
#[expected_failure(abort_code = eve_bridge::E_NOT_IN_GLOBAL)]
fun test_factory_owner_cannot_create_new_mapping() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    setup_bridge(&mut scenario);

    scenario.next_tx(admin);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        let factory_id = object::id_from_address(@0xFA);
        // Type 99999 never added to global → E_NOT_IN_GLOBAL
        eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 99999);

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

// ============================================================
// 7. Multiple factories — independent overrides
// ============================================================
#[test]
fun test_multiple_factories_independent_overrides() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    setup_bridge(&mut scenario);

    scenario.next_tx(admin);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));

        let factory_a = object::id_from_address(@0xA1);
        let factory_b = object::id_from_address(@0xB2);

        // Disable for factory A only
        eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_a, 12001);

        // Factory A → none
        let res_a = eve_bridge::resolve_eve_to_industrial_for_factory(&registry, factory_a, 12001);
        assert!(res_a.is_none());

        // Factory B → still resolves
        let res_b = eve_bridge::resolve_eve_to_industrial_for_factory(&registry, factory_b, 12001);
        assert!(res_b.is_some());
        assert!(*res_b.borrow() == string::utf8(b"tritanium"));

        // Global → still works
        let global = eve_bridge::resolve_eve_to_industrial(&registry, 12001);
        assert!(global.is_some());

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

// ============================================================
// 8. Admin revoke nonexistent pass — should succeed (just marks ID as revoked)
// ============================================================
#[test]
fun test_admin_revoke_nonexistent_pass() {
    let owner = @0xAA;
    let mut scenario = test_scenario::begin(owner);
    setup_access(&mut scenario);

    scenario.next_tx(owner);
    {
        let inputs = vector[recipe::new_material_req(1001, 10)];
        let output = recipe::new_material_output(2001, 1);
        let r = recipe::create_recipe(
            string::utf8(b"R"), inputs, output, 60000, 100, scenario.ctx(),
        );
        let recipe_id = recipe::recipe_id(&r);
        production_line::create_production_line(
            string::utf8(b"L"), recipe_id, scenario.ctx(),
        );
        transfer::public_transfer(r, owner);
    };

    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();

        // Fabricate a random pass_id that was never a real pass
        let fake_pass_id = object::id_from_address(@0xDEAD);

        factory_access::admin_revoke_pass(
            &mut access_reg, fake_pass_id, @0xDEAD, &line, scenario.ctx(),
        );

        // Should now show as revoked
        assert!(factory_access::is_pass_revoked(&access_reg, fake_pass_id));

        test_scenario::return_shared(line);
        test_scenario::return_shared(access_reg);
    };
    scenario.end();
}

// ============================================================
// 9. Surrender then reclaim — same factory, same user
// ============================================================
#[test]
fun test_surrender_then_reclaim() {
    let owner = @0xAA;
    let mut scenario = test_scenario::begin(owner);
    setup_access(&mut scenario);
    setup_line_and_bpo(&mut scenario, owner);

    // Claim
    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
        factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());
        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_reg);
    };

    // Surrender
    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let pass = scenario.take_from_sender<AccessPass>();
        factory_access::surrender_pass(&mut access_reg, pass, scenario.ctx());
        test_scenario::return_shared(access_reg);
    };

    // Reclaim — should succeed because active_passes entry was removed
    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
        factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());
        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_reg);
    };

    // Verify new pass exists
    scenario.next_tx(owner);
    {
        assert!(test_scenario::has_most_recent_for_address<AccessPass>(owner));
        let pass = scenario.take_from_sender<AccessPass>();
        assert!(factory_access::pass_holder(&pass) == owner);
        scenario.return_to_sender(pass);
    };
    scenario.end();
}

// ============================================================
// 10. Two different users claim passes for same factory
// ============================================================
#[test]
fun test_claim_as_different_users() {
    let owner = @0xAA;
    let user_b = @0xBB;
    let mut scenario = test_scenario::begin(owner);
    setup_access(&mut scenario);

    // Create recipe, line, and 2 BPOs (one for each user)
    scenario.next_tx(owner);
    {
        let inputs = vector[recipe::new_material_req(1001, 10)];
        let output = recipe::new_material_output(2001, 1);
        let r = recipe::create_recipe(
            string::utf8(b"SharedRecipe"),
            inputs,
            output,
            60000,
            100,
            scenario.ctx(),
        );
        let recipe_id = recipe::recipe_id(&r);
        production_line::create_production_line(
            string::utf8(b"SharedLine"),
            recipe_id,
            scenario.ctx(),
        );
        let bpo_a = blueprint::mint_bpo(&r, 0, 10, 5, scenario.ctx());
        let bpo_b = blueprint::mint_bpo(&r, 0, 10, 5, scenario.ctx());
        transfer::public_transfer(bpo_a, owner);
        transfer::public_transfer(bpo_b, user_b);
        transfer::public_transfer(r, owner);
    };

    // User A claims
    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
        factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());
        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_reg);
    };

    // User B claims same factory
    scenario.next_tx(user_b);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
        factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());
        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_reg);
    };

    // Verify both have passes
    scenario.next_tx(owner);
    {
        assert!(test_scenario::has_most_recent_for_address<AccessPass>(owner));
        let pass_a = scenario.take_from_address<AccessPass>(owner);
        assert!(factory_access::pass_holder(&pass_a) == owner);
        test_scenario::return_to_address(owner, pass_a);
    };
    scenario.next_tx(user_b);
    {
        assert!(test_scenario::has_most_recent_for_address<AccessPass>(user_b));
        let pass_b = scenario.take_from_address<AccessPass>(user_b);
        assert!(factory_access::pass_holder(&pass_b) == user_b);
        test_scenario::return_to_address(user_b, pass_b);
    };
    scenario.end();
}

// ============================================================
// BONUS: Double-surrender should fail (pass already consumed)
// This is enforced by Move's linear type system — pass is moved into
// surrender_pass, so a second call can't compile. But we can verify
// surrender of someone else's pass fails.
// ============================================================
#[test]
#[expected_failure(abort_code = factory_access::E_NOT_PASS_HOLDER)]
fun test_surrender_by_non_holder_fails() {
    let owner = @0xAA;
    let thief = @0xCC;
    let mut scenario = test_scenario::begin(owner);
    setup_access(&mut scenario);
    setup_line_and_bpo(&mut scenario, owner);

    // Owner claims
    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
        factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());
        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_reg);
    };

    // Thief tries to surrender owner's pass
    scenario.next_tx(thief);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let pass = scenario.take_from_address<AccessPass>(owner);
        factory_access::surrender_pass(&mut access_reg, pass, scenario.ctx());
        test_scenario::return_shared(access_reg);
    };
    scenario.end();
}

// ============================================================
// BONUS: Revoke expired on non-expirable pass → E_PASS_NOT_EXPIRABLE
// ============================================================
#[test]
#[expected_failure(abort_code = factory_access::E_PASS_NOT_EXPIRABLE)]
fun test_revoke_expired_on_non_expirable_pass() {
    let owner = @0xAA;
    let mut scenario = test_scenario::begin(owner);
    setup_access(&mut scenario);
    setup_line_and_bpo(&mut scenario, owner);

    // Claim blueprint pass (no expiry)
    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let bpo = scenario.take_from_sender<industrial_core::blueprint::BlueprintOriginal>();
        let line = scenario.take_shared<industrial_core::production_line::ProductionLine>();
        factory_access::claim_from_blueprint(&mut access_reg, &bpo, &line, scenario.ctx());
        scenario.return_to_sender(bpo);
        test_scenario::return_shared(line);
        test_scenario::return_shared(access_reg);
    };

    // Try revoke_expired — blueprint passes have no expiry
    scenario.next_tx(owner);
    {
        let mut access_reg = scenario.take_shared<AccessRegistry>();
        let pass = scenario.take_from_sender<AccessPass>();
        let clock = sui::clock::create_for_testing(scenario.ctx());
        factory_access::revoke_expired(&mut access_reg, pass, &clock);
        sui::clock::destroy_for_testing(clock);
        test_scenario::return_shared(access_reg);
    };
    scenario.end();
}

// ============================================================
// BONUS: Disable same type twice for same factory → VecSet insert duplicate
// ============================================================
#[test]
#[expected_failure]
fun test_disable_same_type_twice_for_factory() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    setup_bridge(&mut scenario);

    scenario.next_tx(admin);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));

        let factory_id = object::id_from_address(@0xFA);
        eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 12001);
        // Second disable → VecSet::insert aborts (EKeyAlreadyExists = 0)
        eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 12001);

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

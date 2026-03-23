#[test_only]
module work_order::fleet_integration_tests;

use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;
use work_order::work_order::{Self, WorkOrder, WorkOrderBoard};
use work_order::fleet_integration;

const ISSUER: address = @0xA;

fun dummy_recipe_id(): ID {
    object::id_from_address(@0xDEAD)
}

#[test]
fun test_create_order_from_damage_report() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);

        let payment = coin::mint_for_testing<SUI>(5_000_000, scenario.ctx());
        fleet_integration::create_order_from_damage_report(
            &mut board,
            b"Emergency hull repair".to_string(),
            dummy_recipe_id(),
            3,
            payment,
            1_000_000,
            b"FLEET_EVT_001".to_string(),
            &clk,
            scenario.ctx(),
        );

        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.next_tx(ISSUER);
    {
        let order = scenario.take_shared<WorkOrder>();
        // Priority must be CRITICAL (2)
        assert!(work_order::order_priority(&order) == 2);
        // source_event must be set
        let src = work_order::order_source_event(&order);
        assert!(std::option::is_some(src));
        test_scenario::return_shared(order);
    };
    scenario.end();
}

#[test]
fun test_damage_report_fields_preserved() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);

        let payment = coin::mint_for_testing<SUI>(2_000_000, scenario.ctx());
        fleet_integration::create_order_from_damage_report(
            &mut board,
            b"Shield capacitor".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            500_000,
            b"DMG_REPORT_42".to_string(),
            &clk,
            scenario.ctx(),
        );

        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.next_tx(ISSUER);
    {
        let order = scenario.take_shared<WorkOrder>();
        assert!(work_order::order_priority(&order) == 2);

        let src_opt = work_order::order_source_event(&order);
        assert!(std::option::is_some(src_opt));
        let src = std::option::borrow(src_opt);
        assert!(*src == b"DMG_REPORT_42".to_string());

        assert!(work_order::order_quantity_required(&order) == 1);
        assert!(work_order::order_escrow_value(&order) == 2_000_000);
        test_scenario::return_shared(order);
    };
    scenario.end();
}

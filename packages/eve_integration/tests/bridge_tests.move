#[test_only]
module eve_integration::bridge_tests;

use std::string;
use sui::test_scenario;
use eve_integration::eve_bridge::{Self, GlobalRegistry, RegistryAdminCap};

#[test]
fun test_init_creates_registry_and_cap() {
    let mut scenario = test_scenario::begin(@0xAD);
    {
        eve_bridge::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAD);
    {
        assert!(test_scenario::has_most_recent_shared<GlobalRegistry>());
        assert!(test_scenario::has_most_recent_for_address<RegistryAdminCap>(@0xAD));
    };
    scenario.end();
}

#[test]
fun test_add_and_resolve_global_mapping() {
    let mut scenario = test_scenario::begin(@0xAD);
    {
        eve_bridge::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAD);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        eve_bridge::add_global_mapping(
            &mut registry, &cap, 12001, string::utf8(b"tritanium"),
        );

        let result = eve_bridge::resolve_eve_to_industrial(&registry, 12001);
        assert!(result.is_some());
        assert!(*result.borrow() == string::utf8(b"tritanium"));

        let reverse = eve_bridge::resolve_industrial_to_eve(&registry, string::utf8(b"tritanium"));
        assert!(reverse.is_some());
        assert!(*reverse.borrow() == 12001);

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

#[test]
fun test_remove_global_mapping() {
    let mut scenario = test_scenario::begin(@0xAD);
    {
        eve_bridge::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAD);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));
        eve_bridge::remove_global_mapping(&mut registry, &cap, 12001);

        let result = eve_bridge::resolve_eve_to_industrial(&registry, 12001);
        assert!(result.is_none());

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

#[test]
fun test_factory_override_disables_mapping() {
    let mut scenario = test_scenario::begin(@0xAD);
    {
        eve_bridge::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAD);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));

        let factory_id = object::id_from_address(@0xFA);
        eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 12001);

        // Global still works
        let global_result = eve_bridge::resolve_eve_to_industrial(&registry, 12001);
        assert!(global_result.is_some());

        // Factory-specific is disabled
        let factory_result = eve_bridge::resolve_eve_to_industrial_for_factory(
            &registry, factory_id, 12001,
        );
        assert!(factory_result.is_none());

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = eve_bridge::E_NOT_IN_GLOBAL)]
fun test_disable_nonexistent_mapping_fails() {
    let mut scenario = test_scenario::begin(@0xAD);
    {
        eve_bridge::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAD);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();
        let factory_id = object::id_from_address(@0xFA);

        eve_bridge::disable_factory_mapping_admin(&mut registry, &cap, factory_id, 99999);

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = eve_bridge::E_MAPPING_ALREADY_EXISTS)]
fun test_add_duplicate_mapping_fails() {
    let mut scenario = test_scenario::begin(@0xAD);
    {
        eve_bridge::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAD);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));
        eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"pyerite"));

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

#[test]
fun test_has_global_mapping() {
    let mut scenario = test_scenario::begin(@0xAD);
    {
        eve_bridge::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(@0xAD);
    {
        let mut registry = scenario.take_shared<GlobalRegistry>();
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        assert!(!eve_bridge::has_global_mapping(&registry, 12001));
        eve_bridge::add_global_mapping(&mut registry, &cap, 12001, string::utf8(b"tritanium"));
        assert!(eve_bridge::has_global_mapping(&registry, 12001));

        scenario.return_to_sender(cap);
        test_scenario::return_shared(registry);
    };
    scenario.end();
}

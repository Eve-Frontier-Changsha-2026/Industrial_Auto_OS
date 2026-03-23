#[test_only]
module industrial_core::recipe_tests;

use industrial_core::recipe;
use std::unit_test::destroy;

#[test]
fun test_create_recipe_valid() {
    let mut ctx = tx_context::dummy();
    let inputs = vector[recipe::new_material_req(101, 500)];
    let output = recipe::new_material_output(201, 1);
    let r = recipe::create_recipe(
        b"Frigate Hull".to_string(),
        inputs,
        output,
        60_000,
        100,
        &mut ctx,
    );
    assert!(recipe::name(&r) == b"Frigate Hull".to_string());
    assert!(recipe::energy_cost(&r) == 100);
    assert!(recipe::base_duration_ms(&r) == 60_000);
    assert!(recipe::inputs(&r).length() == 1);
    destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_RECIPE_EMPTY_INPUTS)]
fun test_create_recipe_empty_inputs_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[],
        recipe::new_material_output(201, 1),
        60_000,
        100,
        &mut ctx,
    );
    destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_RECIPE_ZERO_QUANTITY)]
fun test_create_recipe_zero_input_quantity_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[recipe::new_material_req(101, 0)],
        recipe::new_material_output(201, 1),
        60_000,
        100,
        &mut ctx,
    );
    destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_RECIPE_ZERO_QUANTITY)]
fun test_create_recipe_zero_output_quantity_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[recipe::new_material_req(101, 500)],
        recipe::new_material_output(201, 0),
        60_000,
        100,
        &mut ctx,
    );
    destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_INVALID_RECIPE)]
fun test_create_recipe_zero_duration_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[recipe::new_material_req(101, 500)],
        recipe::new_material_output(201, 1),
        0,
        100,
        &mut ctx,
    );
    destroy(r);
}

#[test]
#[expected_failure(abort_code = recipe::E_INVALID_RECIPE)]
fun test_create_recipe_zero_energy_fails() {
    let mut ctx = tx_context::dummy();
    let r = recipe::create_recipe(
        b"Bad".to_string(),
        vector[recipe::new_material_req(101, 500)],
        recipe::new_material_output(201, 1),
        60_000,
        0,
        &mut ctx,
    );
    destroy(r);
}

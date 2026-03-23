module industrial_core::recipe;

use std::string::String;

// === Error Codes ===
const E_INVALID_RECIPE: u64 = 10;
const E_RECIPE_EMPTY_INPUTS: u64 = 15;
const E_RECIPE_ZERO_QUANTITY: u64 = 16;

// === Structs ===
public struct MaterialRequirement has store, copy, drop {
    item_type_id: u32,
    quantity: u64,
}

public struct MaterialOutput has store, copy, drop {
    item_type_id: u32,
    quantity: u64,
}

public struct Recipe has key, store {
    id: UID,
    name: String,
    inputs: vector<MaterialRequirement>,
    output: MaterialOutput,
    base_duration_ms: u64,
    energy_cost: u64,
    creator: address,
}

// === Constructors ===
public fun new_material_req(item_type_id: u32, quantity: u64): MaterialRequirement {
    MaterialRequirement { item_type_id, quantity }
}

public fun new_material_output(item_type_id: u32, quantity: u64): MaterialOutput {
    MaterialOutput { item_type_id, quantity }
}

/// Creates a Recipe object. Caller decides transfer/wrap in PTB.
/// In tests, use std::unit_test::destroy().
public fun create_recipe(
    name: String,
    inputs: vector<MaterialRequirement>,
    output: MaterialOutput,
    base_duration_ms: u64,
    energy_cost: u64,
    ctx: &mut TxContext,
): Recipe {
    assert!(inputs.length() > 0, E_RECIPE_EMPTY_INPUTS);
    assert!(output.quantity > 0, E_RECIPE_ZERO_QUANTITY);
    assert!(base_duration_ms > 0, E_INVALID_RECIPE);
    assert!(energy_cost > 0, E_INVALID_RECIPE);
    // Validate each input has quantity > 0
    let mut i = 0;
    while (i < inputs.length()) {
        assert!(inputs[i].quantity > 0, E_RECIPE_ZERO_QUANTITY);
        i = i + 1;
    };
    Recipe {
        id: object::new(ctx),
        name,
        inputs,
        output,
        base_duration_ms,
        energy_cost,
        creator: ctx.sender(),
    }
}

// === Accessors ===
public fun name(r: &Recipe): String { r.name }
public fun inputs(r: &Recipe): &vector<MaterialRequirement> { &r.inputs }
public fun output(r: &Recipe): &MaterialOutput { &r.output }
public fun base_duration_ms(r: &Recipe): u64 { r.base_duration_ms }
public fun energy_cost(r: &Recipe): u64 { r.energy_cost }
public fun creator(r: &Recipe): address { r.creator }
public fun recipe_id(r: &Recipe): ID { r.id.to_inner() }

public fun req_item_type_id(req: &MaterialRequirement): u32 { req.item_type_id }
public fun req_quantity(req: &MaterialRequirement): u64 { req.quantity }
public fun output_item_type_id(out: &MaterialOutput): u32 { out.item_type_id }
public fun output_quantity(out: &MaterialOutput): u64 { out.quantity }

/// Check if a given item_type_id is in the recipe inputs
public fun has_input_type(r: &Recipe, item_type_id: u32): bool {
    let mut i = 0;
    while (i < r.inputs.length()) {
        if (r.inputs[i].item_type_id == item_type_id) {
            return true
        };
        i = i + 1;
    };
    false
}

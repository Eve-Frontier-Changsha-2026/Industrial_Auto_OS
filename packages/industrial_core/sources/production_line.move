module industrial_core::production_line;

use std::string::String;
use sui::bag::{Self, Bag};
use sui::vec_set::{Self, VecSet};
use sui::clock::Clock;
use sui::event;
use industrial_core::recipe::{Self, Recipe};
use industrial_core::blueprint::BlueprintOriginal;

// === Error Codes ===
const E_NOT_OWNER: u64 = 0;
const E_NOT_AUTHORIZED_OPERATOR: u64 = 1;
const E_INSUFFICIENT_MATERIALS: u64 = 2;
const E_PRODUCTION_LINE_BUSY: u64 = 3;
const E_PRODUCTION_NOT_COMPLETE: u64 = 4;
const E_RECIPE_BLUEPRINT_MISMATCH: u64 = 11;
const E_INSUFFICIENT_FUEL: u64 = 12;
const E_ZERO_MATERIAL_AFTER_EFFICIENCY: u64 = 14;
const E_MAX_OPERATORS_REACHED: u64 = 17;
const E_INVALID_ITEM_TYPE: u64 = 18;
const E_INSUFFICIENT_OUTPUT: u64 = 20;

// === Constants ===
const MAX_OPERATORS: u64 = 10;
const STATUS_IDLE: u8 = 0;
const STATUS_RUNNING: u8 = 1;

// === Structs ===
public struct ProductionLine has key {
    id: UID,
    name: String,
    owner: address,
    authorized_operators: VecSet<address>,
    recipe_id: ID,
    input_buffer: Bag,
    output_buffer: Bag,
    fuel_reserve: u64,
    status: u8,
    current_job_start: u64,
    current_job_end: u64,
    jobs_completed: u64,
}

// === Events ===
public struct ProductionStartedEvent has copy, drop {
    production_line_id: ID,
    recipe_id: ID,
    operator: address,
    estimated_completion: u64,
}

public struct ProductionCompletedEvent has copy, drop {
    production_line_id: ID,
    output_item_type_id: u32,
    output_quantity: u64,
    timestamp: u64,
    jobs_completed: u64,
}

// === Auth Helpers ===
fun require_owner(line: &ProductionLine, ctx: &TxContext) {
    assert!(ctx.sender() == line.owner, E_NOT_OWNER);
}

fun require_owner_or_operator(line: &ProductionLine, ctx: &TxContext) {
    let sender = ctx.sender();
    if (sender == line.owner) return;
    assert!(line.authorized_operators.contains(&sender), E_NOT_AUTHORIZED_OPERATOR);
}

// === Entry Functions ===

/// Create a new production line as a shared object.
public entry fun create_production_line(
    name: String,
    recipe_id: ID,
    ctx: &mut TxContext,
) {
    let line = ProductionLine {
        id: object::new(ctx),
        name,
        owner: ctx.sender(),
        authorized_operators: vec_set::empty(),
        recipe_id,
        input_buffer: bag::new(ctx),
        output_buffer: bag::new(ctx),
        fuel_reserve: 0,
        status: STATUS_IDLE,
        current_job_start: 0,
        current_job_end: 0,
        jobs_completed: 0,
    };
    transfer::share_object(line);
}

/// Owner adds an operator. Max 10 operators.
public entry fun authorize_operator(
    line: &mut ProductionLine,
    operator: address,
    ctx: &TxContext,
) {
    require_owner(line, ctx);
    assert!(line.authorized_operators.size() < MAX_OPERATORS, E_MAX_OPERATORS_REACHED);
    line.authorized_operators.insert(operator);
}

/// Owner removes an operator.
public entry fun revoke_operator(
    line: &mut ProductionLine,
    operator: address,
    ctx: &TxContext,
) {
    require_owner(line, ctx);
    line.authorized_operators.remove(&operator);
}

/// Owner deposits materials. Validates item_type_id against recipe inputs.
public entry fun deposit_materials(
    line: &mut ProductionLine,
    recipe: &Recipe,
    item_type_id: u32,
    quantity: u64,
    ctx: &TxContext,
) {
    require_owner(line, ctx);
    assert!(recipe::has_input_type(recipe, item_type_id), E_INVALID_ITEM_TYPE);
    bag_add_or_increment(&mut line.input_buffer, item_type_id, quantity);
}

/// Owner deposits fuel.
public entry fun deposit_fuel(
    line: &mut ProductionLine,
    amount: u64,
    ctx: &TxContext,
) {
    require_owner(line, ctx);
    line.fuel_reserve = line.fuel_reserve + amount;
}

/// Owner withdraws output. Operator cannot.
public entry fun withdraw_output(
    line: &mut ProductionLine,
    item_type_id: u32,
    quantity: u64,
    ctx: &TxContext,
) {
    require_owner(line, ctx);
    let current = bag_get_qty(&line.output_buffer, item_type_id);
    assert!(current >= quantity, E_INSUFFICIENT_OUTPUT);
    bag_deduct(&mut line.output_buffer, item_type_id, quantity);
}

// === Public Functions (for PTB composition) ===

/// Start production using a BPO.
public fun start_production(
    line: &mut ProductionLine,
    recipe: &Recipe,
    blueprint: &BlueprintOriginal,
    clock: &Clock,
    ctx: &TxContext,
) {
    require_owner_or_operator(line, ctx);
    let bpo_recipe_id = industrial_core::blueprint::bpo_recipe_id(blueprint);
    assert!(bpo_recipe_id == object::id(recipe), E_RECIPE_BLUEPRINT_MISMATCH);
    let me = industrial_core::blueprint::bpo_material_efficiency(blueprint);
    let te = industrial_core::blueprint::bpo_time_efficiency(blueprint);
    start_production_internal(line, recipe, me, te, clock, ctx);
}

/// Start production using BPC efficiency values (from use_bpc result).
public fun start_production_with_efficiency(
    line: &mut ProductionLine,
    recipe: &Recipe,
    me: u8,
    te: u8,
    clock: &Clock,
    ctx: &TxContext,
) {
    require_owner_or_operator(line, ctx);
    start_production_internal(line, recipe, me, te, clock, ctx);
}

/// Complete production after time has elapsed.
public fun complete_production(
    line: &mut ProductionLine,
    clock: &Clock,
    ctx: &TxContext,
) {
    require_owner_or_operator(line, ctx);
    assert!(line.status == STATUS_RUNNING, E_PRODUCTION_LINE_BUSY);
    let now = clock.timestamp_ms();
    assert!(now >= line.current_job_end, E_PRODUCTION_NOT_COMPLETE);

    line.status = STATUS_IDLE;
    line.jobs_completed = line.jobs_completed + 1;

    // Add output — recipe output is stored in the line's recipe_id but we need
    // to emit the event. For simplicity, we store the output info during start.
    // Actually, we need to know output item_type_id and quantity.
    // We'll store them as fields during start_production_internal.
    let output_item = line.current_output_item_type_id();
    let output_qty = line.current_output_quantity();
    bag_add_or_increment(&mut line.output_buffer, output_item, output_qty);

    event::emit(ProductionCompletedEvent {
        production_line_id: line.id.to_inner(),
        output_item_type_id: output_item,
        output_quantity: output_qty,
        timestamp: now,
        jobs_completed: line.jobs_completed,
    });
}

// === Internal ===

fun start_production_internal(
    line: &mut ProductionLine,
    recipe: &Recipe,
    me: u8,
    te: u8,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(line.recipe_id == object::id(recipe), E_RECIPE_BLUEPRINT_MISMATCH);
    assert!(line.status == STATUS_IDLE, E_PRODUCTION_LINE_BUSY);

    // Deduct materials with efficiency (ceiling division, u128)
    let inputs = recipe.inputs();
    let mut i = 0;
    while (i < inputs.length()) {
        let req = &inputs[i];
        let base_qty = recipe::req_quantity(req);
        let actual_qty = ceiling_efficiency(base_qty, me);
        assert!(actual_qty >= 1, E_ZERO_MATERIAL_AFTER_EFFICIENCY);

        let item_type_id = recipe::req_item_type_id(req);
        let available = bag_get_qty(&line.input_buffer, item_type_id);
        assert!(available >= actual_qty, E_INSUFFICIENT_MATERIALS);
        bag_deduct(&mut line.input_buffer, item_type_id, actual_qty);
        i = i + 1;
    };

    // Deduct fuel
    let energy = recipe.energy_cost();
    assert!(line.fuel_reserve >= energy, E_INSUFFICIENT_FUEL);
    line.fuel_reserve = line.fuel_reserve - energy;

    // Calculate duration with time efficiency
    let base_duration = recipe.base_duration_ms();
    let actual_duration = ceiling_efficiency(base_duration, te);

    let now = clock.timestamp_ms();
    line.status = STATUS_RUNNING;
    line.current_job_start = now;
    line.current_job_end = now + actual_duration;

    // Store output info for complete_production
    let output = recipe.output();
    store_current_output(line, recipe::output_item_type_id(output), recipe::output_quantity(output));

    event::emit(ProductionStartedEvent {
        production_line_id: line.id.to_inner(),
        recipe_id: line.recipe_id,
        operator: ctx.sender(),
        estimated_completion: line.current_job_end,
    });
}

/// Ceiling division: ((base * (100 - efficiency)) + 99) / 100
/// Uses u128 to prevent overflow.
fun ceiling_efficiency(base: u64, efficiency: u8): u64 {
    let base128 = (base as u128);
    let factor = ((100 - (efficiency as u128)) as u128);
    let result = ((base128 * factor + 99) / 100 as u64);
    result
}

// === Bag Helpers ===

fun bag_get_qty(b: &Bag, item_type_id: u32): u64 {
    if (b.contains(item_type_id)) {
        *b.borrow<u32, u64>(item_type_id)
    } else {
        0
    }
}

fun bag_add_or_increment(b: &mut Bag, item_type_id: u32, quantity: u64) {
    if (b.contains(item_type_id)) {
        let current: &mut u64 = b.borrow_mut(item_type_id);
        *current = *current + quantity;
    } else {
        b.add(item_type_id, quantity);
    }
}

fun bag_deduct(b: &mut Bag, item_type_id: u32, quantity: u64) {
    let current: &mut u64 = b.borrow_mut(item_type_id);
    *current = *current - quantity;
}

// Store current output info using dynamic fields on the Bag
// We use special keys to avoid collision with item_type_ids
// Using a separate approach: store in reserved fields via the UID
fun store_current_output(line: &mut ProductionLine, item_type_id: u32, quantity: u64) {
    // Use output_buffer as temp storage with a sentinel key
    // Actually, simpler: add fields to ProductionLine struct
    // But we can't change struct after creation...
    // Use dynamic fields on the ProductionLine's UID
    let uid = &mut line.id;
    if (sui::dynamic_field::exists_(uid, b"output_item")) {
        *sui::dynamic_field::borrow_mut(uid, b"output_item") = item_type_id;
        *sui::dynamic_field::borrow_mut(uid, b"output_qty") = quantity;
    } else {
        sui::dynamic_field::add(uid, b"output_item", item_type_id);
        sui::dynamic_field::add(uid, b"output_qty", quantity);
    };
}

fun current_output_item_type_id(line: &ProductionLine): u32 {
    *sui::dynamic_field::borrow(&line.id, b"output_item")
}

fun current_output_quantity(line: &ProductionLine): u64 {
    *sui::dynamic_field::borrow(&line.id, b"output_qty")
}

// === Package-internal Functions ===

/// Add fuel without auth check. For mock_fuel and trigger_engine.
public(package) fun add_fuel_internal(line: &mut ProductionLine, amount: u64) {
    line.fuel_reserve = line.fuel_reserve + amount;
}

/// Get recipe_id for trigger engine validation.
public(package) fun get_recipe_id(line: &ProductionLine): ID {
    line.recipe_id
}

/// Get input buffer qty for trigger engine evaluation.
public(package) fun get_input_buffer_qty(line: &ProductionLine, item_type_id: u32): u64 {
    bag_get_qty(&line.input_buffer, item_type_id)
}

/// Get output buffer qty for trigger engine evaluation.
public(package) fun get_output_buffer_qty(line: &ProductionLine, item_type_id: u32): u64 {
    bag_get_qty(&line.output_buffer, item_type_id)
}

// === Accessors ===
public fun owner(line: &ProductionLine): address { line.owner }
public fun status(line: &ProductionLine): u8 { line.status }
public fun jobs_completed(line: &ProductionLine): u64 { line.jobs_completed }
public fun fuel_reserve(line: &ProductionLine): u64 { line.fuel_reserve }
public fun recipe_id_of(line: &ProductionLine): ID { line.recipe_id }
public fun current_job_end(line: &ProductionLine): u64 { line.current_job_end }

public fun input_buffer_qty(line: &ProductionLine, item_type_id: u32): u64 {
    bag_get_qty(&line.input_buffer, item_type_id)
}

public fun output_buffer_qty(line: &ProductionLine, item_type_id: u32): u64 {
    bag_get_qty(&line.output_buffer, item_type_id)
}

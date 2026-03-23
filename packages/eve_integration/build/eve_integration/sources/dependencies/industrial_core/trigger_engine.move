module industrial_core::trigger_engine;

use sui::clock::Clock;
use sui::event;
use industrial_core::recipe::Recipe;
use industrial_core::blueprint::BlueprintOriginal;
use industrial_core::production_line::{Self, ProductionLine};

// === Error Codes ===
const E_NOT_OWNER: u64 = 0;
const E_TRIGGER_DISABLED: u64 = 7;
const E_TRIGGER_CONDITION_NOT_MET: u64 = 8;
const E_TRIGGER_COOLDOWN: u64 = 9;
const E_TRIGGER_LINE_MISMATCH: u64 = 19;

// === Condition Types ===
const CONDITION_INVENTORY_BELOW: u8 = 0;
const CONDITION_INVENTORY_ABOVE: u8 = 1;
// const CONDITION_EXTERNAL_EVENT: u8 = 2;  // future
// const CONDITION_SCHEDULE: u8 = 3;        // future

// === Structs ===
public struct TriggerRule has key, store {
    id: UID,
    production_line_id: ID,
    condition_type: u8,
    threshold: u64,
    target_item_type_id: u32,
    auto_repeat: bool,
    enabled: bool,
    last_triggered: u64,
    cooldown_ms: u64,
}

// === Events ===
public struct TriggerFiredEvent has copy, drop {
    trigger_rule_id: ID,
    production_line_id: ID,
    condition_type: u8,
    timestamp: u64,
}

// === Functions ===

/// Create a trigger rule. Only the production line owner can create rules.
public fun create_trigger_rule(
    line: &ProductionLine,
    condition_type: u8,
    threshold: u64,
    target_item_type_id: u32,
    auto_repeat: bool,
    cooldown_ms: u64,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == production_line::owner(line), E_NOT_OWNER);
    let rule = TriggerRule {
        id: object::new(ctx),
        production_line_id: object::id(line),
        condition_type,
        threshold,
        target_item_type_id,
        auto_repeat,
        enabled: true,
        last_triggered: 0,
        cooldown_ms,
    };
    transfer::transfer(rule, ctx.sender());
}

/// Toggle trigger enabled/disabled.
public fun toggle_trigger(rule: &mut TriggerRule, enabled: bool) {
    rule.enabled = enabled;
}

/// Evaluate if trigger condition is met. Pure read — no state changes.
/// Returns true if trigger should fire.
public fun evaluate_trigger(
    rule: &TriggerRule,
    line: &ProductionLine,
    clock: &Clock,
): bool {
    if (!rule.enabled) return false;

    // Check cooldown
    let now = clock.timestamp_ms();
    if (rule.cooldown_ms > 0 && rule.last_triggered > 0) {
        if (now < rule.last_triggered + rule.cooldown_ms) return false;
    };

    // Check line is idle
    if (production_line::status(line) != 0) return false;

    // Check condition
    if (rule.condition_type == CONDITION_INVENTORY_BELOW) {
        let current_qty = production_line::get_output_buffer_qty(line, rule.target_item_type_id);
        return current_qty < rule.threshold
    };
    if (rule.condition_type == CONDITION_INVENTORY_ABOVE) {
        let current_qty = production_line::get_output_buffer_qty(line, rule.target_item_type_id);
        return current_qty > rule.threshold
    };

    false
}

/// Execute trigger: re-evaluate on-chain (TOCTOU protection), then start production.
public fun execute_trigger(
    rule: &mut TriggerRule,
    line: &mut ProductionLine,
    recipe: &Recipe,
    blueprint: &BlueprintOriginal,
    clock: &Clock,
    ctx: &TxContext,
) {
    // Validate rule matches this production line
    assert!(rule.production_line_id == object::id(line), E_TRIGGER_LINE_MISMATCH);

    // Re-evaluate on-chain (TOCTOU protection)
    assert!(rule.enabled, E_TRIGGER_DISABLED);
    let now = clock.timestamp_ms();
    if (rule.cooldown_ms > 0 && rule.last_triggered > 0) {
        assert!(now >= rule.last_triggered + rule.cooldown_ms, E_TRIGGER_COOLDOWN);
    };
    assert!(evaluate_condition(rule, line), E_TRIGGER_CONDITION_NOT_MET);

    // Start production
    production_line::start_production(line, recipe, blueprint, clock, ctx);

    // Update trigger state
    rule.last_triggered = now;
    if (!rule.auto_repeat) {
        rule.enabled = false;
    };

    event::emit(TriggerFiredEvent {
        trigger_rule_id: rule.id.to_inner(),
        production_line_id: rule.production_line_id,
        condition_type: rule.condition_type,
        timestamp: now,
    });
}

// === Internal ===

fun evaluate_condition(rule: &TriggerRule, line: &ProductionLine): bool {
    if (rule.condition_type == CONDITION_INVENTORY_BELOW) {
        let current_qty = production_line::get_output_buffer_qty(line, rule.target_item_type_id);
        return current_qty < rule.threshold
    };
    if (rule.condition_type == CONDITION_INVENTORY_ABOVE) {
        let current_qty = production_line::get_output_buffer_qty(line, rule.target_item_type_id);
        return current_qty > rule.threshold
    };
    false
}

// === Accessors ===
public fun rule_production_line_id(rule: &TriggerRule): ID { rule.production_line_id }
public fun rule_condition_type(rule: &TriggerRule): u8 { rule.condition_type }
public fun rule_threshold(rule: &TriggerRule): u64 { rule.threshold }
public fun rule_target_item_type_id(rule: &TriggerRule): u32 { rule.target_item_type_id }
public fun rule_enabled(rule: &TriggerRule): bool { rule.enabled }
public fun rule_last_triggered(rule: &TriggerRule): u64 { rule.last_triggered }
public fun rule_cooldown_ms(rule: &TriggerRule): u64 { rule.cooldown_ms }

// === Test Helpers ===
#[test_only]
public fun set_last_triggered_for_testing(rule: &mut TriggerRule, ts: u64) {
    rule.last_triggered = ts;
}

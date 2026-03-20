module work_order::fleet_integration;

use std::string::String;
use sui::coin::Coin;
use sui::sui::SUI;
use sui::clock::Clock;
use work_order::work_order::{Self, WorkOrderBoard};

const PRIORITY_CRITICAL: u8 = 2;

/// Create a work order from a Fleet Command damage report.
/// Auto-sets priority to critical and stores source_event.
public fun create_order_from_damage_report(
    board: &mut WorkOrderBoard,
    description: String,
    recipe_id: ID,
    quantity: u64,
    payment: Coin<SUI>,
    deadline: u64,
    source_event: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    work_order::create_work_order_with_source(
        board,
        description,
        recipe_id,
        quantity,
        payment,
        deadline,
        PRIORITY_CRITICAL,
        option::some(source_event),
        clock,
        ctx,
    );
}

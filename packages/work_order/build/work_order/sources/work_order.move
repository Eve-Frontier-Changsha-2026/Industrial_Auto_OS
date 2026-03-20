module work_order::work_order;

use std::string::String;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::clock::Clock;
use sui::event;

// === Constants ===
const STATUS_OPEN: u8       = 0;
const STATUS_ACCEPTED: u8   = 1;
const STATUS_DELIVERING: u8 = 2;
const STATUS_DELIVERED: u8  = 3;
const STATUS_COMPLETED: u8  = 4;
const STATUS_CANCELLED: u8  = 5;

const MIN_ESCROW: u64   = 1_000_000;                       // 1 MIST
const MAX_DEADLINE: u64 = 30 * 24 * 60 * 60 * 1000;       // 30 days in ms
const AUTO_COMPLETE_DELAY: u64 = 72 * 60 * 60 * 1000;     // 72 hours in ms

// === Error Codes ===
const E_INSUFFICIENT_ESCROW: u64       = 100;
const E_DEADLINE_TOO_FAR: u64          = 101;
const E_ORDER_ALREADY_ACCEPTED: u64    = 102;
const E_NOT_ISSUER: u64                = 103;
const E_NOT_ACCEPTOR: u64              = 104;
const E_WRONG_STATUS: u64              = 105;
#[allow(unused_const)]
const E_DELIVERY_TYPE_MISMATCH: u64    = 106;
const E_DELIVERY_QUANTITY_EXCEEDS: u64 = 107;
const E_NOT_EXPIRED: u64               = 108;
const E_NOT_DELIVERED: u64             = 109;
const E_AUTO_COMPLETE_TOO_EARLY: u64   = 110;

// === Structs ===

/// Shared board tracking all active work order IDs.
public struct WorkOrderBoard has key {
    id: UID,
    orders: Table<ID, bool>,
}

/// A work order with escrowed SUI payment.
/// No `store` ability because it contains Balance<SUI>.
public struct WorkOrder has key {
    id: UID,
    issuer: address,
    description: String,
    recipe_id: ID,
    quantity_required: u64,
    quantity_delivered: u64,
    escrow: Balance<SUI>,
    deadline: u64,
    status: u8,
    acceptor: Option<address>,
    priority: u8,
    source_event: Option<String>,
    delivered_at: Option<u64>,
}

// === Events ===

public struct WorkOrderCreated has copy, drop {
    order_id: ID,
    issuer: address,
    recipe_id: ID,
    quantity_required: u64,
    escrow_amount: u64,
    deadline: u64,
    priority: u8,
}

public struct WorkOrderAccepted has copy, drop {
    order_id: ID,
    acceptor: address,
}

public struct WorkOrderDelivered has copy, drop {
    order_id: ID,
    acceptor: address,
    quantity_delivered: u64,
    quantity_required: u64,
    status: u8,
}

public struct WorkOrderCompleted has copy, drop {
    order_id: ID,
    issuer: address,
    acceptor: address,
    escrow_released: u64,
}

public struct WorkOrderCancelled has copy, drop {
    order_id: ID,
    issuer: address,
    refunded: u64,
}

// === Init ===

/// Creates the shared WorkOrderBoard on publish.
fun init(ctx: &mut TxContext) {
    transfer::share_object(WorkOrderBoard {
        id: object::new(ctx),
        orders: table::new(ctx),
    });
}

// === Public Functions ===

/// Create a work order with no source event.
public fun create_work_order(
    board: &mut WorkOrderBoard,
    description: String,
    recipe_id: ID,
    quantity: u64,
    payment: Coin<SUI>,
    deadline: u64,
    priority: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    create_work_order_with_source(
        board,
        description,
        recipe_id,
        quantity,
        payment,
        deadline,
        priority,
        option::none(),
        clock,
        ctx,
    );
}

/// Create a work order with an optional source_event string (used by fleet_integration).
public fun create_work_order_with_source(
    board: &mut WorkOrderBoard,
    description: String,
    recipe_id: ID,
    quantity: u64,
    payment: Coin<SUI>,
    deadline: u64,
    priority: u8,
    source_event: Option<String>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let escrow_amount = payment.value();
    assert!(escrow_amount >= MIN_ESCROW, E_INSUFFICIENT_ESCROW);
    assert!(deadline <= clock.timestamp_ms() + MAX_DEADLINE, E_DEADLINE_TOO_FAR);

    let order = WorkOrder {
        id: object::new(ctx),
        issuer: ctx.sender(),
        description,
        recipe_id,
        quantity_required: quantity,
        quantity_delivered: 0,
        escrow: payment.into_balance(),
        deadline,
        status: STATUS_OPEN,
        acceptor: option::none(),
        priority,
        source_event,
        delivered_at: option::none(),
    };

    let order_id = order.id.to_inner();
    board.orders.add(order_id, true);

    event::emit(WorkOrderCreated {
        order_id,
        issuer: ctx.sender(),
        recipe_id,
        quantity_required: quantity,
        escrow_amount,
        deadline,
        priority,
    });

    transfer::share_object(order);
}

/// Accept an open work order. Any address can become the acceptor.
public fun accept_work_order(order: &mut WorkOrder, ctx: &mut TxContext) {
    assert!(order.status == STATUS_OPEN, E_ORDER_ALREADY_ACCEPTED);
    order.status = STATUS_ACCEPTED;
    order.acceptor = option::some(ctx.sender());

    event::emit(WorkOrderAccepted {
        order_id: order.id.to_inner(),
        acceptor: ctx.sender(),
    });
}

/// Record delivery progress. Caller must be the acceptor.
/// Pass item_type_id for tracking; quantity adds to quantity_delivered.
/// Status becomes DELIVERING (partial) or DELIVERED (full).
public fun deliver_work_order(
    order: &mut WorkOrder,
    _item_type_id: u32,
    quantity: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(
        order.acceptor == option::some(sender),
        E_NOT_ACCEPTOR,
    );
    assert!(
        order.status == STATUS_ACCEPTED || order.status == STATUS_DELIVERING,
        E_WRONG_STATUS,
    );
    let new_delivered = order.quantity_delivered + quantity;
    assert!(new_delivered <= order.quantity_required, E_DELIVERY_QUANTITY_EXCEEDS);

    order.quantity_delivered = new_delivered;

    if (new_delivered == order.quantity_required) {
        order.status = STATUS_DELIVERED;
        order.delivered_at = option::some(clock.timestamp_ms());
    } else {
        order.status = STATUS_DELIVERING;
    };

    event::emit(WorkOrderDelivered {
        order_id: order.id.to_inner(),
        acceptor: sender,
        quantity_delivered: new_delivered,
        quantity_required: order.quantity_required,
        status: order.status,
    });
}

/// Issuer confirms delivery and releases escrow to acceptor.
public fun complete_work_order(
    order: &mut WorkOrder,
    board: &mut WorkOrderBoard,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == order.issuer, E_NOT_ISSUER);
    assert!(order.status == STATUS_DELIVERED, E_NOT_DELIVERED);

    let acceptor = *option::borrow(&order.acceptor);
    let escrow_amount = order.escrow.value();

    release_escrow_to_acceptor(order, board, acceptor, escrow_amount, ctx);
}

/// Acceptor triggers auto-complete 72h after delivery without issuer action.
public fun auto_complete_work_order(
    order: &mut WorkOrder,
    board: &mut WorkOrderBoard,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(
        order.acceptor == option::some(sender),
        E_NOT_ACCEPTOR,
    );
    assert!(order.status == STATUS_DELIVERED, E_NOT_DELIVERED);

    let delivered_at = *option::borrow(&order.delivered_at);
    assert!(
        clock.timestamp_ms() >= delivered_at + AUTO_COMPLETE_DELAY,
        E_AUTO_COMPLETE_TOO_EARLY,
    );

    let escrow_amount = order.escrow.value();
    release_escrow_to_acceptor(order, board, sender, escrow_amount, ctx);
}

/// Issuer cancels an OPEN order (before any acceptor). Full refund.
public fun cancel_work_order(
    order: &mut WorkOrder,
    board: &mut WorkOrderBoard,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == order.issuer, E_NOT_ISSUER);
    assert!(order.status == STATUS_OPEN, E_WRONG_STATUS);

    let issuer = order.issuer;
    let refund = order.escrow.value();
    refund_and_close(order, board, issuer, refund, ctx);
}

/// Anyone can cancel an expired order. Refund splits based on status.
/// OPEN => full refund to issuer
/// ACCEPTED / DELIVERING => 90% to issuer, 10% to acceptor
public fun cancel_expired_order(
    order: &mut WorkOrder,
    board: &mut WorkOrderBoard,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(clock.timestamp_ms() > order.deadline, E_NOT_EXPIRED);
    assert!(
        order.status == STATUS_OPEN ||
        order.status == STATUS_ACCEPTED ||
        order.status == STATUS_DELIVERING,
        E_WRONG_STATUS,
    );

    let issuer = order.issuer;
    let total = order.escrow.value();

    if (order.status == STATUS_OPEN) {
        refund_and_close(order, board, issuer, total, ctx);
    } else {
        // 90% to issuer, 10% to acceptor
        let acceptor = *option::borrow(&order.acceptor);
        let acceptor_share = total / 10;
        let issuer_share = total - acceptor_share;

        // Split acceptor share out first, then refund issuer
        let acceptor_balance = balance::split(&mut order.escrow, acceptor_share);
        transfer::public_transfer(
            coin::from_balance(acceptor_balance, ctx),
            acceptor,
        );

        refund_and_close(order, board, issuer, issuer_share, ctx);
    };
}

// === Internal Helpers ===

fun release_escrow_to_acceptor(
    order: &mut WorkOrder,
    board: &mut WorkOrderBoard,
    acceptor: address,
    _escrow_amount: u64,
    ctx: &mut TxContext,
) {
    let issuer = order.issuer;
    let escrow_amount = order.escrow.value();
    order.status = STATUS_COMPLETED;
    let order_id = order.id.to_inner();
    board.orders.remove(order_id);

    // Drain escrow
    let payout = balance::split(&mut order.escrow, escrow_amount);
    transfer::public_transfer(
        coin::from_balance(payout, ctx),
        acceptor,
    );

    event::emit(WorkOrderCompleted {
        order_id,
        issuer,
        acceptor,
        escrow_released: escrow_amount,
    });
}

fun refund_and_close(
    order: &mut WorkOrder,
    board: &mut WorkOrderBoard,
    recipient: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    let issuer = order.issuer;
    order.status = STATUS_CANCELLED;
    let order_id = order.id.to_inner();
    board.orders.remove(order_id);

    let refund_balance = balance::split(&mut order.escrow, amount);
    transfer::public_transfer(
        coin::from_balance(refund_balance, ctx),
        recipient,
    );

    event::emit(WorkOrderCancelled {
        order_id,
        issuer,
        refunded: amount,
    });
}

// === Test-only init helper ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

// === Accessors ===
public fun order_issuer(order: &WorkOrder): address          { order.issuer }
public fun order_description(order: &WorkOrder): &String     { &order.description }
public fun order_recipe_id(order: &WorkOrder): ID            { order.recipe_id }
public fun order_quantity_required(order: &WorkOrder): u64   { order.quantity_required }
public fun order_quantity_delivered(order: &WorkOrder): u64  { order.quantity_delivered }
public fun order_escrow_value(order: &WorkOrder): u64        { order.escrow.value() }
public fun order_deadline(order: &WorkOrder): u64            { order.deadline }
public fun order_status(order: &WorkOrder): u8               { order.status }
public fun order_acceptor(order: &WorkOrder): Option<address> { order.acceptor }
public fun order_priority(order: &WorkOrder): u8             { order.priority }
public fun order_source_event(order: &WorkOrder): &Option<String> { &order.source_event }
public fun order_delivered_at(order: &WorkOrder): Option<u64> { order.delivered_at }

public fun board_contains(board: &WorkOrderBoard, order_id: ID): bool {
    board.orders.contains(order_id)
}

// === Status Constants Accessors ===
public fun status_open(): u8       { STATUS_OPEN }
public fun status_accepted(): u8   { STATUS_ACCEPTED }
public fun status_delivering(): u8 { STATUS_DELIVERING }
public fun status_delivered(): u8  { STATUS_DELIVERED }
public fun status_completed(): u8  { STATUS_COMPLETED }
public fun status_cancelled(): u8  { STATUS_CANCELLED }

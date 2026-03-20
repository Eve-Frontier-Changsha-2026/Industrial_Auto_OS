#[test_only]
module work_order::monkey_tests;

use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;
use work_order::work_order::{Self, WorkOrder, WorkOrderBoard};
use work_order::fleet_integration;

const ISSUER: address   = @0xA;
const ACCEPTOR: address = @0xB;
const OTHER: address    = @0xC;
const NOBODY: address   = @0xD;

const AUTO_COMPLETE_DELAY: u64 = 72 * 60 * 60 * 1000; // 72h in ms

fun dummy_recipe_id(): ID { object::id_from_address(@0xDEAD) }

fun make_escrow(amount: u64, ctx: &mut TxContext): coin::Coin<SUI> {
    coin::mint_for_testing<SUI>(amount, ctx)
}

/// Helper: create board + order with given params, returns scenario after order is shared.
/// Caller must call scenario.next_tx(...) to access the order.
fun setup_order(
    escrow: u64,
    quantity: u64,
    deadline: u64,
    clock_now: u64,
): test_scenario::Scenario {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(clock_now);
        let payment = make_escrow(escrow, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"monkey".to_string(),
            dummy_recipe_id(),
            quantity,
            payment,
            deadline,
            0,
            &clk,
            scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario
}

/// Helper: create + accept order
fun setup_accepted_order(
    escrow: u64,
    quantity: u64,
    deadline: u64,
    clock_now: u64,
): test_scenario::Scenario {
    let mut scenario = setup_order(escrow, quantity, deadline, clock_now);
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        work_order::accept_work_order(&mut order, scenario.ctx());
        test_scenario::return_shared(order);
    };
    scenario
}

/// Helper: create + accept + fully deliver order
fun setup_delivered_order(
    escrow: u64,
    quantity: u64,
    deadline: u64,
    deliver_time: u64,
): test_scenario::Scenario {
    let mut scenario = setup_accepted_order(escrow, quantity, deadline, 0);
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(deliver_time);
        work_order::deliver_work_order(&mut order, 101, quantity, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario
}

// ============================================================================
// 1. BOUNDARY VALUE: zero payment (below MIN_ESCROW)
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_INSUFFICIENT_ESCROW)]
fun monkey_zero_payment() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(0, scenario.ctx());
        work_order::create_work_order(
            &mut board, b"zero".to_string(), dummy_recipe_id(),
            1, payment, 1_000, 0, &clk, scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 2. BOUNDARY VALUE: exact MIN_ESCROW (should succeed)
// ============================================================================
#[test]
fun monkey_exact_min_escrow() {
    let mut scenario = setup_order(1_000_000, 1, 1_000_000, 0);
    scenario.next_tx(ISSUER);
    {
        let order = scenario.take_shared<WorkOrder>();
        assert!(work_order::order_escrow_value(&order) == 1_000_000);
        test_scenario::return_shared(order);
    };
    scenario.end();
}

// ============================================================================
// 3. BOUNDARY VALUE: deadline exactly at MAX_DEADLINE boundary (should succeed)
// ============================================================================
#[test]
fun monkey_deadline_at_max_boundary() {
    let max_deadline: u64 = 30 * 24 * 60 * 60 * 1000;
    let now: u64 = 5_000;
    let mut scenario = setup_order(1_000_000, 1, now + max_deadline, now);
    scenario.next_tx(ISSUER);
    {
        let order = scenario.take_shared<WorkOrder>();
        assert!(work_order::order_status(&order) == work_order::status_open());
        test_scenario::return_shared(order);
    };
    scenario.end();
}

// ============================================================================
// 4. BOUNDARY VALUE: deadline 1ms past MAX_DEADLINE (should fail)
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_DEADLINE_TOO_FAR)]
fun monkey_deadline_1ms_over_max() {
    let max_deadline: u64 = 30 * 24 * 60 * 60 * 1000;
    let now: u64 = 5_000;
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(now);
        let payment = make_escrow(1_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board, b"over".to_string(), dummy_recipe_id(),
            1, payment, now + max_deadline + 1, 0, &clk, scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 5. STATE MACHINE: complete an OPEN order (not delivered) → E_NOT_DELIVERED
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_DELIVERED)]
fun monkey_complete_open_order() {
    let mut scenario = setup_order(1_000_000, 1, 1_000_000, 0);
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::complete_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.end();
}

// ============================================================================
// 6. STATE MACHINE: complete an ACCEPTED (not delivered) order → E_NOT_DELIVERED
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_DELIVERED)]
fun monkey_complete_accepted_not_delivered() {
    let mut scenario = setup_accepted_order(1_000_000, 5, 1_000_000, 0);
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::complete_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.end();
}

// ============================================================================
// 7. STATE MACHINE: complete a DELIVERING (partial) order → E_NOT_DELIVERED
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_DELIVERED)]
fun monkey_complete_partially_delivered() {
    let mut scenario = setup_accepted_order(1_000_000, 10, 1_000_000, 0);
    // Deliver only 3 of 10
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 3, &clk, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_delivering());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::complete_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.end();
}

// ============================================================================
// 8. PERMISSION: non-issuer tries to cancel open order → E_NOT_ISSUER
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_ISSUER)]
fun monkey_cancel_by_stranger() {
    let mut scenario = setup_order(1_000_000, 1, 1_000_000, 0);
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::cancel_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.end();
}

// ============================================================================
// 9. PERMISSION: non-acceptor tries to deliver → E_NOT_ACCEPTOR
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_ACCEPTOR)]
fun monkey_deliver_by_stranger() {
    let mut scenario = setup_accepted_order(1_000_000, 5, 1_000_000, 0);
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 1, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 10. PERMISSION: issuer tries to deliver own order → E_NOT_ACCEPTOR
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_ACCEPTOR)]
fun monkey_issuer_delivers_own_order() {
    let mut scenario = setup_accepted_order(1_000_000, 5, 1_000_000, 0);
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 1, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 11. PERMISSION: non-acceptor tries auto_complete → E_NOT_ACCEPTOR
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_ACCEPTOR)]
fun monkey_auto_complete_by_stranger() {
    let mut scenario = setup_delivered_order(1_000_000, 1, 1_000_000_000, 1_000);
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_000 + AUTO_COMPLETE_DELAY + 1);
        work_order::auto_complete_work_order(&mut order, &mut board, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 12. TIME ATTACK: auto_complete exactly at boundary (too early by 1ms)
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_AUTO_COMPLETE_TOO_EARLY)]
fun monkey_auto_complete_1ms_too_early() {
    let deliver_time: u64 = 10_000;
    let mut scenario = setup_delivered_order(1_000_000, 1, 1_000_000_000, deliver_time);
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        // exactly at deliver_time + AUTO_COMPLETE_DELAY - 1 → too early
        clk.set_for_testing(deliver_time + AUTO_COMPLETE_DELAY - 1);
        work_order::auto_complete_work_order(&mut order, &mut board, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 13. TIME ATTACK: auto_complete exactly at boundary (should succeed at exact delay)
// ============================================================================
#[test]
fun monkey_auto_complete_exact_boundary() {
    let deliver_time: u64 = 10_000;
    let mut scenario = setup_delivered_order(1_000_000, 1, 1_000_000_000, deliver_time);
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(deliver_time + AUTO_COMPLETE_DELAY);
        work_order::auto_complete_work_order(&mut order, &mut board, &clk, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_completed());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 14. EXPIRED: cancel_expired exactly at deadline (should fail, need > not >=)
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_EXPIRED)]
fun monkey_cancel_expired_at_exact_deadline() {
    let deadline: u64 = 5_000;
    let mut scenario = setup_order(1_000_000, 1, deadline, 0);
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(deadline); // exactly at deadline, not past
        work_order::cancel_expired_order(&mut order, &mut board, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 15. EXPIRED: cancel_expired on a DELIVERED order → E_WRONG_STATUS
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_WRONG_STATUS)]
fun monkey_cancel_expired_delivered_order() {
    // deadline=5000, deliver at t=100, expire check at t=5001
    let mut scenario = setup_delivered_order(1_000_000, 1, 5_000, 100);
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(5_001);
        work_order::cancel_expired_order(&mut order, &mut board, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 16. DELIVERY OVERFLOW: deliver quantity that would overflow u64
// ============================================================================
#[test]
#[expected_failure] // arithmetic overflow
fun monkey_deliver_u64_overflow() {
    let mut scenario = setup_accepted_order(1_000_000, 18_446_744_073_709_551_615, 1_000_000, 0);
    // Deliver 1 first to set quantity_delivered = 1
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 1, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    // Then deliver MAX_U64 → overflow on addition
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(200);
        work_order::deliver_work_order(&mut order, 101, 18_446_744_073_709_551_615, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 17. STATE MACHINE: deliver on OPEN order (no acceptor set) → E_NOT_ACCEPTOR
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_ACCEPTOR)]
fun monkey_deliver_on_open_order() {
    let mut scenario = setup_order(1_000_000, 5, 1_000_000, 0);
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 1, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 18. STATE MACHINE: cancel_expired on already COMPLETED order → E_WRONG_STATUS
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_WRONG_STATUS)]
fun monkey_cancel_expired_completed_order() {
    let mut scenario = setup_delivered_order(1_000_000, 1, 1_000_000_000, 100);
    // Issuer completes
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::complete_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    // Try cancel_expired on completed
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_000_000_001);
        work_order::cancel_expired_order(&mut order, &mut board, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 19. STATE MACHINE: cancel_expired on already CANCELLED order → E_WRONG_STATUS
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_WRONG_STATUS)]
fun monkey_cancel_expired_cancelled_order() {
    let mut scenario = setup_order(1_000_000, 1, 1_000, 0);
    // Issuer cancels (open order)
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::cancel_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    // Try cancel_expired on already cancelled
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_001);
        work_order::cancel_expired_order(&mut order, &mut board, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 20. ESCROW: cancel_expired with DELIVERING splits 90/10 correctly
// ============================================================================
#[test]
fun monkey_cancel_expired_delivering_splits_correctly() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        // Use 7_000_000 for non-trivial split: 10% = 700_000, 90% = 6_300_000
        let payment = make_escrow(7_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board, b"split".to_string(), dummy_recipe_id(),
            10, payment, 2_000, 0, &clk, scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        work_order::accept_work_order(&mut order, scenario.ctx());
        test_scenario::return_shared(order);
    };
    // Partial deliver (3 of 10) → DELIVERING
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(500);
        work_order::deliver_work_order(&mut order, 101, 3, &clk, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_delivering());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    // Expire
    scenario.next_tx(NOBODY);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(2_001);
        work_order::cancel_expired_order(&mut order, &mut board, &clk, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_cancelled());
        assert!(work_order::order_escrow_value(&order) == 0);
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    // Acceptor gets 10% = 700_000
    scenario.next_tx(ACCEPTOR);
    {
        let coins = scenario.take_from_sender<coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 700_000);
        scenario.return_to_sender(coins);
    };
    // Issuer gets 90% = 6_300_000
    scenario.next_tx(ISSUER);
    {
        let coins = scenario.take_from_sender<coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 6_300_000);
        scenario.return_to_sender(coins);
    };
    scenario.end();
}

// ============================================================================
// 21. ESCROW: MIN_ESCROW expired split → acceptor gets 100_000, issuer 900_000
// ============================================================================
#[test]
fun monkey_min_escrow_expired_split() {
    let mut scenario = setup_accepted_order(1_000_000, 1, 1_000, 0);
    // Expire after acceptance
    scenario.next_tx(NOBODY);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_001);
        work_order::cancel_expired_order(&mut order, &mut board, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.next_tx(ACCEPTOR);
    {
        let coins = scenario.take_from_sender<coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 100_000); // 10% of 1_000_000
        scenario.return_to_sender(coins);
    };
    scenario.next_tx(ISSUER);
    {
        let coins = scenario.take_from_sender<coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 900_000); // 90%
        scenario.return_to_sender(coins);
    };
    scenario.end();
}

// ============================================================================
// 22. DUPLICATE OP: accept an already-completed order → E_ORDER_ALREADY_ACCEPTED
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_ORDER_ALREADY_ACCEPTED)]
fun monkey_accept_completed_order() {
    let mut scenario = setup_delivered_order(1_000_000, 1, 1_000_000_000, 100);
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::complete_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.next_tx(NOBODY);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        work_order::accept_work_order(&mut order, scenario.ctx());
        test_scenario::return_shared(order);
    };
    scenario.end();
}

// ============================================================================
// 23. DUPLICATE OP: accept a cancelled order → E_ORDER_ALREADY_ACCEPTED
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_ORDER_ALREADY_ACCEPTED)]
fun monkey_accept_cancelled_order() {
    let mut scenario = setup_order(1_000_000, 1, 1_000_000, 0);
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::cancel_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.next_tx(NOBODY);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        work_order::accept_work_order(&mut order, scenario.ctx());
        test_scenario::return_shared(order);
    };
    scenario.end();
}

// ============================================================================
// 24. STATE MACHINE: auto_complete on ACCEPTED (not delivered) → E_NOT_DELIVERED
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_DELIVERED)]
fun monkey_auto_complete_not_delivered() {
    let mut scenario = setup_accepted_order(1_000_000, 1, 1_000_000_000, 0);
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(AUTO_COMPLETE_DELAY + 1_000_000);
        work_order::auto_complete_work_order(&mut order, &mut board, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 25. DELIVERY: deliver 0 quantity (stays DELIVERING, no progress)
// ============================================================================
#[test]
fun monkey_deliver_zero_quantity() {
    let mut scenario = setup_accepted_order(1_000_000, 5, 1_000_000, 0);
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 0, &clk, scenario.ctx());
        assert!(work_order::order_quantity_delivered(&order) == 0);
        // Still delivering (or accepted? 0 != 5, so DELIVERING)
        assert!(work_order::order_status(&order) == work_order::status_delivering());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 26. FLEET INTEGRATION: damage report with zero payment → E_INSUFFICIENT_ESCROW
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_INSUFFICIENT_ESCROW)]
fun monkey_fleet_damage_report_zero_payment() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(0, scenario.ctx());
        fleet_integration::create_order_from_damage_report(
            &mut board, b"broken".to_string(), dummy_recipe_id(),
            1, payment, 1_000, b"EVT_0".to_string(), &clk, scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 27. FULL LIFECYCLE: create → accept → partial deliver → full deliver → complete
// ============================================================================
#[test]
fun monkey_full_lifecycle_multi_delivery() {
    let mut scenario = setup_accepted_order(5_000_000, 100, 1_000_000, 0);
    // Deliver in 4 batches: 25, 25, 25, 25
    let mut i: u64 = 0;
    while (i < 4) {
        scenario.next_tx(ACCEPTOR);
        {
            let mut order = scenario.take_shared<WorkOrder>();
            let mut clk = clock::create_for_testing(scenario.ctx());
            clk.set_for_testing(100 + i * 100);
            work_order::deliver_work_order(&mut order, 101, 25, &clk, scenario.ctx());
            if (i < 3) {
                assert!(work_order::order_status(&order) == work_order::status_delivering());
            } else {
                assert!(work_order::order_status(&order) == work_order::status_delivered());
            };
            test_scenario::return_shared(order);
            clk.destroy_for_testing();
        };
        i = i + 1;
    };
    // Complete
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::complete_work_order(&mut order, &mut board, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_completed());
        assert!(work_order::order_escrow_value(&order) == 0);
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.end();
}

// ============================================================================
// 28. PERMISSION: acceptor tries to cancel open order → E_NOT_ISSUER
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_NOT_ISSUER)]
fun monkey_acceptor_cancels_order() {
    let mut scenario = setup_order(1_000_000, 1, 1_000_000, 0);
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::cancel_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.end();
}

// ============================================================================
// 29. DELIVERY EXCEEDS: partial delivery then exceed remainder
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_DELIVERY_QUANTITY_EXCEEDS)]
fun monkey_partial_then_exceed() {
    let mut scenario = setup_accepted_order(1_000_000, 10, 1_000_000, 0);
    // Deliver 7
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 7, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    // Deliver 4 more → 7+4=11 > 10
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(200);
        work_order::deliver_work_order(&mut order, 101, 4, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

// ============================================================================
// 30. STATE MACHINE: cancel open order then try accept → E_ORDER_ALREADY_ACCEPTED
// ============================================================================
#[test]
#[expected_failure(abort_code = work_order::E_ORDER_ALREADY_ACCEPTED)]
fun monkey_cancel_then_accept() {
    let mut scenario = setup_order(1_000_000, 1, 1_000_000, 0);
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::cancel_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        work_order::accept_work_order(&mut order, scenario.ctx());
        test_scenario::return_shared(order);
    };
    scenario.end();
}

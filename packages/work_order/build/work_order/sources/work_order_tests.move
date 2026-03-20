#[test_only]
module work_order::work_order_tests;

use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;
use work_order::work_order::{Self, WorkOrder, WorkOrderBoard};

const ISSUER: address   = @0xA;
const ACCEPTOR: address = @0xB;
const OTHER: address    = @0xC;

// Helpers

fun dummy_recipe_id(): ID {
    object::id_from_address(@0xDEAD)
}

fun make_escrow(amount: u64, ctx: &mut TxContext): sui::coin::Coin<SUI> {
    coin::mint_for_testing<SUI>(amount, ctx)
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[test]
fun test_create_work_order_with_escrow() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_000);

        let payment = make_escrow(5_000_000, scenario.ctx());
        let deadline = 1_000 + 1_000_000; // well within 30 days

        work_order::create_work_order(
            &mut board,
            b"Build hull".to_string(),
            dummy_recipe_id(),
            10,
            payment,
            deadline,
            0,
            &clk,
            scenario.ctx(),
        );

        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.next_tx(ISSUER);
    {
        let order = scenario.take_shared<WorkOrder>();
        assert!(work_order::order_escrow_value(&order) == 5_000_000);
        assert!(work_order::order_status(&order) == work_order::status_open());
        assert!(work_order::order_quantity_required(&order) == 10);
        test_scenario::return_shared(order);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = work_order::E_INSUFFICIENT_ESCROW)]
fun test_create_order_below_min_escrow() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_000);

        // Payment below MIN_ESCROW (1_000_000)
        let payment = make_escrow(999_999, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"fail".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            1_000 + 1_000_000,
            0,
            &clk,
            scenario.ctx(),
        );

        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = work_order::E_DEADLINE_TOO_FAR)]
fun test_create_order_deadline_too_far() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_000);

        let payment = make_escrow(5_000_000, scenario.ctx());
        // deadline = now + 31 days > MAX_DEADLINE (30 days)
        let deadline = 1_000 + 31 * 24 * 60 * 60 * 1_000;

        work_order::create_work_order(
            &mut board,
            b"fail".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            deadline,
            0,
            &clk,
            scenario.ctx(),
        );

        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.end();
}

#[test]
fun test_accept_work_order() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            5,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        work_order::accept_work_order(&mut order, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_accepted());
        assert!(work_order::order_acceptor(&order) == std::option::some(ACCEPTOR));
        test_scenario::return_shared(order);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = work_order::E_ORDER_ALREADY_ACCEPTED)]
fun test_accept_already_accepted() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            5,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
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
    // Second accept (by OTHER) should fail with E_ORDER_ALREADY_ACCEPTED
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        work_order::accept_work_order(&mut order, scenario.ctx());
        test_scenario::return_shared(order);
    };
    scenario.end();
}

#[test]
fun test_deliver_correct() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            10,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
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
    // Partial delivery
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 5, &clk, scenario.ctx());
        assert!(work_order::order_quantity_delivered(&order) == 5);
        assert!(work_order::order_status(&order) == work_order::status_delivering());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    // Full delivery
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(200);
        work_order::deliver_work_order(&mut order, 101, 5, &clk, scenario.ctx());
        assert!(work_order::order_quantity_delivered(&order) == 10);
        assert!(work_order::order_status(&order) == work_order::status_delivered());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = work_order::E_WRONG_STATUS)]
fun test_deliver_wrong_status() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            5,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    // Accept first so acceptor is set, then try delivering on OPEN (impossible directly)
    // Actually we need to set acceptor but keep status OPEN — just try delivering without accept
    // But acceptor is None, so E_NOT_ACCEPTOR (104) fires first.
    // To hit E_WRONG_STATUS we accept, complete delivery, then try delivering again on COMPLETED.
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        work_order::accept_work_order(&mut order, scenario.ctx());
        test_scenario::return_shared(order);
    };
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        // Full delivery
        work_order::deliver_work_order(&mut order, 101, 5, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    // Now status == DELIVERED; trying to deliver again hits E_WRONG_STATUS
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(200);
        work_order::deliver_work_order(&mut order, 101, 1, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = work_order::E_DELIVERY_QUANTITY_EXCEEDS)]
fun test_deliver_exceeds_quantity() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            5,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
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
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        // Deliver 6 when required is 5
        work_order::deliver_work_order(&mut order, 101, 6, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    scenario.end();
}

#[test]
fun test_complete_releases_escrow() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
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
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 1, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
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
    // Acceptor should have received SUI coin
    scenario.next_tx(ACCEPTOR);
    {
        let coins = scenario.take_from_sender<sui::coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 5_000_000);
        scenario.return_to_sender(coins);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = work_order::E_NOT_ISSUER)]
fun test_complete_by_non_issuer() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
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
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(100);
        work_order::deliver_work_order(&mut order, 101, 1, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    // OTHER tries to complete — should fail with E_NOT_ISSUER
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::complete_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.end();
}

#[test]
fun test_cancel_before_accept() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::cancel_work_order(&mut order, &mut board, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_cancelled());
        assert!(work_order::order_escrow_value(&order) == 0);
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    // Issuer gets full refund
    scenario.next_tx(ISSUER);
    {
        let coins = scenario.take_from_sender<sui::coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 5_000_000);
        scenario.return_to_sender(coins);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = work_order::E_WRONG_STATUS)]
fun test_cancel_after_accept() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            1_000_000,
            0,
            &clk,
            scenario.ctx(),
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
    // Cancel after accept should fail with E_WRONG_STATUS
    scenario.next_tx(ISSUER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        work_order::cancel_work_order(&mut order, &mut board, scenario.ctx());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
    };
    scenario.end();
}

#[test]
fun test_cancel_expired_not_accepted() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    // deadline = 1_000
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            1_000,
            0,
            &clk,
            scenario.ctx(),
        );
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    // Time after deadline
    scenario.next_tx(OTHER);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_001);
        work_order::cancel_expired_order(&mut order, &mut board, &clk, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_cancelled());
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    // Issuer gets full refund
    scenario.next_tx(ISSUER);
    {
        let coins = scenario.take_from_sender<sui::coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 5_000_000);
        scenario.return_to_sender(coins);
    };
    scenario.end();
}

#[test]
fun test_cancel_expired_accepted() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        // Use 10_000_000 for easy math (10% = 1_000_000)
        let payment = make_escrow(10_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            5,
            payment,
            1_000,
            0,
            &clk,
            scenario.ctx(),
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
    // Acceptor gets 10%
    scenario.next_tx(ACCEPTOR);
    {
        let coins = scenario.take_from_sender<sui::coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 1_000_000);
        scenario.return_to_sender(coins);
    };
    // Issuer gets 90%
    scenario.next_tx(ISSUER);
    {
        let coins = scenario.take_from_sender<sui::coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 9_000_000);
        scenario.return_to_sender(coins);
    };
    scenario.end();
}

#[test]
fun test_auto_complete_after_72h() {
    let mut scenario = test_scenario::begin(ISSUER);
    {
        work_order::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(ISSUER);
    {
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(0);
        let payment = make_escrow(5_000_000, scenario.ctx());
        work_order::create_work_order(
            &mut board,
            b"test".to_string(),
            dummy_recipe_id(),
            1,
            payment,
            1_000_000_000,
            0,
            &clk,
            scenario.ctx(),
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
    // Deliver at t=1000
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_000);
        work_order::deliver_work_order(&mut order, 101, 1, &clk, scenario.ctx());
        test_scenario::return_shared(order);
        clk.destroy_for_testing();
    };
    // Auto-complete at t = 1000 + 72h + 1ms
    let auto_complete_delay: u64 = 72 * 60 * 60 * 1_000;
    scenario.next_tx(ACCEPTOR);
    {
        let mut order = scenario.take_shared<WorkOrder>();
        let mut board = scenario.take_shared<WorkOrderBoard>();
        let mut clk = clock::create_for_testing(scenario.ctx());
        clk.set_for_testing(1_000 + auto_complete_delay + 1);
        work_order::auto_complete_work_order(&mut order, &mut board, &clk, scenario.ctx());
        assert!(work_order::order_status(&order) == work_order::status_completed());
        assert!(work_order::order_escrow_value(&order) == 0);
        test_scenario::return_shared(order);
        test_scenario::return_shared(board);
        clk.destroy_for_testing();
    };
    // Acceptor received escrow
    scenario.next_tx(ACCEPTOR);
    {
        let coins = scenario.take_from_sender<sui::coin::Coin<SUI>>();
        assert!(coin::value(&coins) == 5_000_000);
        scenario.return_to_sender(coins);
    };
    scenario.end();
}

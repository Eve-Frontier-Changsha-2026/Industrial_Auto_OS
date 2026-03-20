#[test_only]
module industrial_core::blueprint_tests;

use industrial_core::recipe;
use industrial_core::blueprint;
use std::unit_test::destroy;

fun make_test_recipe(ctx: &mut TxContext): recipe::Recipe {
    recipe::create_recipe(
        b"Test Recipe".to_string(),
        vector[recipe::new_material_req(101, 100)],
        recipe::new_material_output(201, 1),
        60_000,
        50,
        ctx,
    )
}

#[test]
fun test_mint_bpo() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let bpo = blueprint::mint_bpo(&r, 10, 15, 20, &mut ctx);
    assert!(blueprint::bpo_material_efficiency(&bpo) == 15);
    assert!(blueprint::bpo_time_efficiency(&bpo) == 20);
    assert!(blueprint::bpo_copies_minted(&bpo) == 0);
    assert!(blueprint::bpo_max_copies(&bpo) == 10);
    destroy(r);
    destroy(bpo);
}

#[test]
#[expected_failure(abort_code = blueprint::E_EFFICIENCY_OUT_OF_RANGE)]
fun test_mint_bpo_me_too_high() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let bpo = blueprint::mint_bpo(&r, 10, 26, 0, &mut ctx);
    destroy(r);
    destroy(bpo);
}

#[test]
#[expected_failure(abort_code = blueprint::E_EFFICIENCY_OUT_OF_RANGE)]
fun test_mint_bpo_te_too_high() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let bpo = blueprint::mint_bpo(&r, 10, 0, 26, &mut ctx);
    destroy(r);
    destroy(bpo);
}

#[test]
fun test_mint_bpc_increments_copies() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 10, 10, 10, &mut ctx);
    let bpc = blueprint::mint_bpc(&mut bpo, 5, &mut ctx);
    assert!(blueprint::bpo_copies_minted(&bpo) == 1);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 5);
    destroy(r);
    destroy(bpo);
    destroy(bpc);
}

#[test]
#[expected_failure(abort_code = blueprint::E_BLUEPRINT_MAX_COPIES_REACHED)]
fun test_mint_bpc_exceeds_max() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 1, 10, 10, &mut ctx);
    let bpc1 = blueprint::mint_bpc(&mut bpo, 5, &mut ctx);
    let bpc2 = blueprint::mint_bpc(&mut bpo, 5, &mut ctx); // should fail
    destroy(r);
    destroy(bpo);
    destroy(bpc1);
    destroy(bpc2);
}

#[test]
fun test_mint_bpc_unlimited_copies() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 15, &mut ctx); // max_copies=0 = unlimited
    let bpc1 = blueprint::mint_bpc(&mut bpo, 3, &mut ctx);
    let bpc2 = blueprint::mint_bpc(&mut bpo, 3, &mut ctx);
    let bpc3 = blueprint::mint_bpc(&mut bpo, 3, &mut ctx);
    assert!(blueprint::bpo_copies_minted(&bpo) == 3);
    destroy(r);
    destroy(bpo);
    destroy(bpc1);
    destroy(bpc2);
    destroy(bpc3);
}

#[test]
fun test_use_bpc_decrements() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 15, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 3, &mut ctx);
    let (recipe_id, me, te) = blueprint::use_bpc(&mut bpc);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 2);
    assert!(me == 10);
    assert!(te == 15);
    let _ = recipe_id;
    destroy(r);
    destroy(bpo);
    destroy(bpc);
}

#[test]
fun test_destroy_empty_bpc() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 10, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 1, &mut ctx);
    let (_, _, _) = blueprint::use_bpc(&mut bpc);
    assert!(blueprint::bpc_uses_remaining(&bpc) == 0);
    blueprint::destroy_empty_bpc(bpc);
    destroy(r);
    destroy(bpo);
}

#[test]
#[expected_failure(abort_code = blueprint::E_BLUEPRINT_NO_USES_LEFT)]
fun test_use_bpc_zero_uses_fails() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 10, &mut ctx);
    let mut bpc = blueprint::mint_bpc(&mut bpo, 1, &mut ctx);
    let (_, _, _) = blueprint::use_bpc(&mut bpc);
    let (_, _, _) = blueprint::use_bpc(&mut bpc); // should fail — 0 uses left
    destroy(r);
    destroy(bpo);
    destroy(bpc);
}

#[test]
#[expected_failure(abort_code = blueprint::E_BLUEPRINT_NO_USES_LEFT)]
fun test_destroy_non_empty_bpc_fails() {
    let mut ctx = tx_context::dummy();
    let r = make_test_recipe(&mut ctx);
    let mut bpo = blueprint::mint_bpo(&r, 0, 10, 10, &mut ctx);
    let bpc = blueprint::mint_bpc(&mut bpo, 2, &mut ctx);
    blueprint::destroy_empty_bpc(bpc); // should fail — 2 uses remain
    destroy(r);
    destroy(bpo);
}

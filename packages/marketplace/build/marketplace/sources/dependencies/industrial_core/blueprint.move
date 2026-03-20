module industrial_core::blueprint;

use industrial_core::recipe::Recipe;

// === Error Codes ===
const E_BLUEPRINT_NO_USES_LEFT: u64 = 5;
const E_BLUEPRINT_MAX_COPIES_REACHED: u64 = 6;
const E_EFFICIENCY_OUT_OF_RANGE: u64 = 13;

// === Structs ===
public struct BlueprintOriginal has key, store {
    id: UID,
    recipe_id: ID,
    copies_minted: u64,
    max_copies: u64,            // 0 = unlimited
    material_efficiency: u8,    // 0-25
    time_efficiency: u8,        // 0-25
}

public struct BlueprintCopy has key, store {
    id: UID,
    recipe_id: ID,
    source_bpo_id: ID,
    uses_remaining: u64,
    material_efficiency: u8,
    time_efficiency: u8,
}

// === Functions ===

/// Mint a new Blueprint Original for a recipe.
/// ME and TE must be <= 25.
public fun mint_bpo(
    recipe: &Recipe,
    max_copies: u64,
    me: u8,
    te: u8,
    ctx: &mut TxContext,
): BlueprintOriginal {
    assert!(me <= 25 && te <= 25, E_EFFICIENCY_OUT_OF_RANGE);
    BlueprintOriginal {
        id: object::new(ctx),
        recipe_id: object::id(recipe),
        copies_minted: 0,
        max_copies,
        material_efficiency: me,
        time_efficiency: te,
    }
}

/// Mint a BPC from a BPO. Requires &mut BPO (only owner can call).
/// Increments copies_minted. Fails if max_copies reached (unless unlimited=0).
public fun mint_bpc(
    bpo: &mut BlueprintOriginal,
    uses: u64,
    ctx: &mut TxContext,
): BlueprintCopy {
    assert!(
        bpo.max_copies == 0 || bpo.copies_minted < bpo.max_copies,
        E_BLUEPRINT_MAX_COPIES_REACHED,
    );
    bpo.copies_minted = bpo.copies_minted + 1;
    BlueprintCopy {
        id: object::new(ctx),
        recipe_id: bpo.recipe_id,
        source_bpo_id: bpo.id.to_inner(),
        uses_remaining: uses,
        material_efficiency: bpo.material_efficiency,
        time_efficiency: bpo.time_efficiency,
    }
}

/// Use one charge of BPC. Returns (recipe_id, ME, TE).
/// Fails if uses_remaining == 0.
public fun use_bpc(bpc: &mut BlueprintCopy): (ID, u8, u8) {
    assert!(bpc.uses_remaining > 0, E_BLUEPRINT_NO_USES_LEFT);
    bpc.uses_remaining = bpc.uses_remaining - 1;
    (bpc.recipe_id, bpc.material_efficiency, bpc.time_efficiency)
}

/// Destroy a BPC with 0 uses remaining.
public fun destroy_empty_bpc(bpc: BlueprintCopy) {
    assert!(bpc.uses_remaining == 0, E_BLUEPRINT_NO_USES_LEFT);
    let BlueprintCopy { id, .. } = bpc;
    id.delete();
}

// === Accessors ===
public fun bpo_recipe_id(bpo: &BlueprintOriginal): ID { bpo.recipe_id }
public fun bpo_copies_minted(bpo: &BlueprintOriginal): u64 { bpo.copies_minted }
public fun bpo_max_copies(bpo: &BlueprintOriginal): u64 { bpo.max_copies }
public fun bpo_material_efficiency(bpo: &BlueprintOriginal): u8 { bpo.material_efficiency }
public fun bpo_time_efficiency(bpo: &BlueprintOriginal): u8 { bpo.time_efficiency }

public fun bpc_recipe_id(bpc: &BlueprintCopy): ID { bpc.recipe_id }
public fun bpc_source_bpo_id(bpc: &BlueprintCopy): ID { bpc.source_bpo_id }
public fun bpc_uses_remaining(bpc: &BlueprintCopy): u64 { bpc.uses_remaining }
public fun bpc_material_efficiency(bpc: &BlueprintCopy): u8 { bpc.material_efficiency }
public fun bpc_time_efficiency(bpc: &BlueprintCopy): u8 { bpc.time_efficiency }

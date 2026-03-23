#[allow(unused_field)]
module eve_integration::events;

use std::string::String;

// === SSU Bridge Events (placeholder — emitted by future SSU functions) ===
public struct SSUWithdrawEvent has copy, drop {
    ssu_id: ID,
    factory_id: ID,
    eve_type_id: u64,
    material_id: String,
    quantity: u32,
    operator: address,
}

public struct SSUDepositEvent has copy, drop {
    ssu_id: ID,
    factory_id: ID,
    eve_type_id: u64,
    material_id: String,
    quantity: u32,
    operator: address,
}

public struct ProductionFromSSUEvent has copy, drop {
    ssu_id: ID,
    factory_id: ID,
    recipe_id: ID,
    input_count: u64,
}

public struct CollectToSSUEvent has copy, drop {
    ssu_id: ID,
    factory_id: ID,
    output_count: u64,
}

public struct PermitIssuedEvent has copy, drop {
    permit_id: ID,
    factory_id: ID,
    character_address: address,
    source_gate_id: ID,
    dest_gate_id: ID,
    expires_at: u64,
}

// === Public constructors for future sibling modules ===
public fun new_ssu_withdraw_event(
    ssu_id: ID, factory_id: ID, eve_type_id: u64,
    material_id: String, quantity: u32, operator: address,
): SSUWithdrawEvent {
    SSUWithdrawEvent { ssu_id, factory_id, eve_type_id, material_id, quantity, operator }
}

public fun new_ssu_deposit_event(
    ssu_id: ID, factory_id: ID, eve_type_id: u64,
    material_id: String, quantity: u32, operator: address,
): SSUDepositEvent {
    SSUDepositEvent { ssu_id, factory_id, eve_type_id, material_id, quantity, operator }
}

public fun new_permit_issued_event(
    permit_id: ID, factory_id: ID, character_address: address,
    source_gate_id: ID, dest_gate_id: ID, expires_at: u64,
): PermitIssuedEvent {
    PermitIssuedEvent { permit_id, factory_id, character_address, source_gate_id, dest_gate_id, expires_at }
}

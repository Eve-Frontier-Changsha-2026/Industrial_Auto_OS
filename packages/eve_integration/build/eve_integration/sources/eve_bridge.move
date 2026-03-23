module eve_integration::eve_bridge;

use std::string::String;
use sui::dynamic_field;
use sui::event;
use sui::vec_set::{Self, VecSet};

// === Error Codes ===
const E_NOT_AUTHORIZED: u64 = 1001;
#[allow(unused_const)]
const E_SSU_OFFLINE: u64 = 1002;
const E_MAPPING_NOT_FOUND: u64 = 1003;
const E_NOT_IN_GLOBAL: u64 = 1004;
#[allow(unused_const)]
const E_QUANTITY_OVERFLOW: u64 = 1005;
#[allow(unused_const)]
const E_FACTORY_MAPPING_DISABLED: u64 = 1006;
const E_MAPPING_ALREADY_EXISTS: u64 = 1007;

// === Events (must be in same module to emit) ===
public struct GlobalMappingAddedEvent has copy, drop {
    eve_type_id: u64,
    material_id: String,
}

public struct GlobalMappingRemovedEvent has copy, drop {
    eve_type_id: u64,
    material_id: String,
}

public struct FactoryMappingDisabledEvent has copy, drop {
    factory_id: ID,
    eve_type_id: u64,
}

public struct FactoryMappingEnabledEvent has copy, drop {
    factory_id: ID,
    eve_type_id: u64,
}

// === Witness ===
public struct IndustrialAuth has drop {}

// === GlobalRegistry ===
public struct GlobalRegistry has key {
    id: UID,
}

public struct RegistryAdminCap has key, store {
    id: UID,
}

// Dynamic field keys for mappings
public struct EveToIndustrial has copy, drop, store { eve_type_id: u64 }
public struct IndustrialToEve has copy, drop, store { material_id: String }

// Factory override
public struct FactoryOverrideKey has copy, drop, store { factory_id: ID }
public struct FactoryOverride has store {
    disabled_types: VecSet<u64>,
}

// === Init ===
fun init(ctx: &mut TxContext) {
    let registry = GlobalRegistry { id: object::new(ctx) };
    let cap = RegistryAdminCap { id: object::new(ctx) };
    transfer::share_object(registry);
    transfer::transfer(cap, ctx.sender());
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

// === Admin: Global Mapping Management ===

public fun add_global_mapping(
    registry: &mut GlobalRegistry,
    _cap: &RegistryAdminCap,
    eve_type_id: u64,
    material_id: String,
) {
    let eve_key = EveToIndustrial { eve_type_id };
    assert!(!dynamic_field::exists_(&registry.id, eve_key), E_MAPPING_ALREADY_EXISTS);
    dynamic_field::add(&mut registry.id, eve_key, material_id);
    dynamic_field::add(&mut registry.id, IndustrialToEve { material_id }, eve_type_id);
    event::emit(GlobalMappingAddedEvent { eve_type_id, material_id });
}

public fun remove_global_mapping(
    registry: &mut GlobalRegistry,
    _cap: &RegistryAdminCap,
    eve_type_id: u64,
) {
    let eve_key = EveToIndustrial { eve_type_id };
    assert!(dynamic_field::exists_(&registry.id, eve_key), E_MAPPING_NOT_FOUND);
    let material_id: String = dynamic_field::remove(&mut registry.id, eve_key);
    dynamic_field::remove<IndustrialToEve, u64>(&mut registry.id, IndustrialToEve { material_id });
    event::emit(GlobalMappingRemovedEvent { eve_type_id, material_id });
}

// === Factory Override ===

public fun disable_factory_mapping_admin(
    registry: &mut GlobalRegistry,
    _cap: &RegistryAdminCap,
    factory_id: ID,
    eve_type_id: u64,
) {
    assert!(dynamic_field::exists_(&registry.id, EveToIndustrial { eve_type_id }), E_NOT_IN_GLOBAL);
    let override_key = FactoryOverrideKey { factory_id };
    if (!dynamic_field::exists_(&registry.id, override_key)) {
        dynamic_field::add(&mut registry.id, override_key, FactoryOverride {
            disabled_types: vec_set::empty(),
        });
    };
    let override_data = dynamic_field::borrow_mut<FactoryOverrideKey, FactoryOverride>(
        &mut registry.id, override_key,
    );
    override_data.disabled_types.insert(eve_type_id);
    event::emit(FactoryMappingDisabledEvent { factory_id, eve_type_id });
}

public fun disable_factory_mapping(
    registry: &mut GlobalRegistry,
    line: &industrial_core::production_line::ProductionLine,
    eve_type_id: u64,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == industrial_core::production_line::owner(line), E_NOT_AUTHORIZED);
    assert!(dynamic_field::exists_(&registry.id, EveToIndustrial { eve_type_id }), E_NOT_IN_GLOBAL);
    let factory_id = object::id(line);
    let override_key = FactoryOverrideKey { factory_id };
    if (!dynamic_field::exists_(&registry.id, override_key)) {
        dynamic_field::add(&mut registry.id, override_key, FactoryOverride {
            disabled_types: vec_set::empty(),
        });
    };
    let override_data = dynamic_field::borrow_mut<FactoryOverrideKey, FactoryOverride>(
        &mut registry.id, override_key,
    );
    override_data.disabled_types.insert(eve_type_id);
    event::emit(FactoryMappingDisabledEvent { factory_id, eve_type_id });
}

public fun enable_factory_mapping(
    registry: &mut GlobalRegistry,
    line: &industrial_core::production_line::ProductionLine,
    eve_type_id: u64,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == industrial_core::production_line::owner(line), E_NOT_AUTHORIZED);
    let factory_id = object::id(line);
    let override_key = FactoryOverrideKey { factory_id };
    assert!(dynamic_field::exists_(&registry.id, override_key), E_MAPPING_NOT_FOUND);
    let override_data = dynamic_field::borrow_mut<FactoryOverrideKey, FactoryOverride>(
        &mut registry.id, override_key,
    );
    override_data.disabled_types.remove(&eve_type_id);
    event::emit(FactoryMappingEnabledEvent { factory_id, eve_type_id });
}

// === Lookup Functions ===

public fun resolve_eve_to_industrial(
    registry: &GlobalRegistry,
    eve_type_id: u64,
): Option<String> {
    let key = EveToIndustrial { eve_type_id };
    if (dynamic_field::exists_(&registry.id, key)) {
        option::some(*dynamic_field::borrow<EveToIndustrial, String>(&registry.id, key))
    } else {
        option::none()
    }
}

public fun resolve_industrial_to_eve(
    registry: &GlobalRegistry,
    material_id: String,
): Option<u64> {
    let key = IndustrialToEve { material_id };
    if (dynamic_field::exists_(&registry.id, key)) {
        option::some(*dynamic_field::borrow<IndustrialToEve, u64>(&registry.id, key))
    } else {
        option::none()
    }
}

public fun resolve_eve_to_industrial_for_factory(
    registry: &GlobalRegistry,
    factory_id: ID,
    eve_type_id: u64,
): Option<String> {
    let override_key = FactoryOverrideKey { factory_id };
    if (dynamic_field::exists_(&registry.id, override_key)) {
        let override_data = dynamic_field::borrow<FactoryOverrideKey, FactoryOverride>(
            &registry.id, override_key,
        );
        if (override_data.disabled_types.contains(&eve_type_id)) {
            return option::none()
        };
    };
    resolve_eve_to_industrial(registry, eve_type_id)
}

public fun has_global_mapping(registry: &GlobalRegistry, eve_type_id: u64): bool {
    dynamic_field::exists_(&registry.id, EveToIndustrial { eve_type_id })
}

// === SSU Registration (placeholder — requires world types) ===
// These functions will be uncommented once world dependency compiles.

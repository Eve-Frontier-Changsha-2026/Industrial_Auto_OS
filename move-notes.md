# Move Notes

## Phase 1: industrial_core (complete — 43 tests)

### Modules
- **recipe**: MaterialRequirement / MaterialOutput / Recipe structs, `create_recipe` with validation
- **blueprint**: BPO (`key, store`) + BPC (`key, store`), `mint_bpo`, `mint_bpc`, `use_bpc`, `destroy_empty_bpc`
- **production_line**: Shared object, owner/operator auth matrix (max 10), Bag-based input/output buffers, dynamic field for current output, `ceiling_efficiency` (u128 safe)
- **trigger_engine**: Threshold triggers with cooldown + TOCTOU safety (`status == IDLE` re-check after material deduction)
- **mock_fuel**: Test helper, deposits fuel without auth

### Known Constraints
- `ProductionLine` has `key` only (Bag blocks `store`)
- Output info stored as dynamic fields on UID (workaround for post-creation struct immutability)
- `package(package)` functions (`add_fuel_internal`, `get_recipe_id`, etc.) for trigger_engine access

---

## Phase 2: work_order (complete — 17 tests)

### Modules
- **work_order**: Full lifecycle — create → accept → deliver → complete/auto-complete (72h) / cancel
  - `WorkOrder` has `key` only (holds `Balance<SUI>`)
  - `WorkOrderBoard` shared object with `Table<ID, bool>`
  - Escrow: full refund on cancel (OPEN), 90/10 split on expired+accepted (`balance::split`)
  - Two create variants: `create_work_order` + `create_work_order_with_source` (for fleet integration)
- **fleet_integration**: Thin wrapper — `create_order_from_damage_report` sets priority=CRITICAL + source_event

### Error Codes: 100-110
### Known Constraints
- `#[error]` annotation breaks `expected_failure(abort_code = N)` — use plain `const`
- `cancel_expired_order` anyone can call (permissionless cleanup)

---

## Phase 3: marketplace (complete — 18 tests)

### Modules
- **marketplace**: BPO/BPC listing/buying with fee
  - `Marketplace` shared object + `MarketplaceAdminCap` owned
  - `BpoListing` / `BpcListing` wrap blueprints by value
  - Fee: `max(1, price * fee_bps / 10000)`, default 250 bps (2.5%), max 1000 bps (10%)
  - `buy_bpo`/`buy_bpc` take `&mut Coin<SUI>`, use `coin::split` for exact payment
  - Admin: `update_fee`, `withdraw_fees`
- **lease**: BPO lease with deposit
  - `LeaseAgreement` shared, holds BPO + `Balance<SUI>` deposit
  - `return_lease` (lessee): BPO → lessor, deposit → lessee
  - `forfeit_lease` (lessor after expiry): BPO + deposit → lessor

### Error Codes: 200-203 (marketplace), 300-302 (lease)
### Known Constraints
- `return_lease` / `forfeit_lease` need `&mut TxContext` (not `&TxContext`) because `coin::from_balance` requires it
- Listings are shared objects (not owned) — anyone can call `buy_*`

# Red Team Report: Industrial Auto OS

> Adversarial security analysis of system spec
> Date: 2026-03-20
> Status: Pre-implementation (spec-level)
> Analyst: sui-red-team

---

## 1. ACCESS CONTROL BYPASS

### 1.1 [CRITICAL] Operator Escalation: Withdraw via Authorized Operator

**Scenario**: `start_production` checks `is_owner || is_authorized_operator`. If implementation copies same auth pattern to `withdraw_output`, an authorized watcher drains the output buffer.

**Impact**: Operator steals all produced goods.

**Countermeasure**: Strict function-level permission matrix. `withdraw_output`, `deposit_materials`, `authorize_operator`, `revoke_operator` = owner-only. Split into `require_owner()` and `require_owner_or_operator()`.

### 1.2 [HIGH] Lease BPO Read-Reference Abuse

**Scenario**: `borrow_leased_bpo()` returns `&BlueprintOriginal`. If `mint_bpc` mistakenly accepts `&BlueprintOriginal` instead of `&mut BlueprintOriginal`, lessee can mint BPCs from leased BPO.

**Impact**: Unlimited BPC minting from unowned BPO.

**Countermeasure**: `mint_bpc` MUST take `bpo: &mut BlueprintOriginal`. Add test: lessee calls mint_bpc with leased BPO -> must abort.

### 1.3 [HIGH] ProductionLine Shared Object Auth Gap

**Scenario**: If `ProductionLine` is shared, anyone can pass `&mut ProductionLine` to any function. Every mutating function must check owner/operator.

**Impact**: Any player can manipulate another's production line.

**Countermeasure**: Either keep as owned object (safer) or assert `sender == owner || is_authorized_operator(sender)` in EVERY mutating function. No exceptions.

### 1.4 [MEDIUM] TriggerRule Creator != ProductionLine Owner

**Scenario**: `create_trigger_rule` takes `line_id: ID` (just an ID). Anyone can create rules pointing to someone else's line. `execute_trigger` must verify `rule.production_line_id == object::id(line)`.

**Impact**: Unauthorized trigger execution.

**Countermeasure**: `create_trigger_rule` should take `&ProductionLine` and verify sender is owner. `execute_trigger` must assert `rule.production_line_id == object::id(line)`.

---

## 2. INTEGER/ARITHMETIC ABUSE

### 2.1 [CRITICAL] Material Efficiency Rounding to Zero

**Scenario**: `actual = base_quantity * (100 - ME) / 100`. If `base_quantity = 1` and `ME = 25`, then `actual = 75 / 100 = 0`. Free production.

**Impact**: Infinite free production.

**Countermeasure**:
```move
let actual = (base_quantity * (100 - (me as u64)) + 99) / 100; // ceiling division
assert!(actual >= 1, E_ZERO_MATERIAL_AFTER_EFFICIENCY);
```

### 2.2 [HIGH] u64 Overflow in Quantity Accumulation

**Scenario**: Deposit `u64::MAX - current + 1` overflows the Bag counter.

**Impact**: Material counter wraps to near-zero.

**Countermeasure**: Move aborts on overflow by default. Never use wrapping arithmetic. Add test: deposit u64::MAX when buffer has 1 -> must abort.

### 2.3 [HIGH] Fee Calculation Rounding Exploit

**Scenario**: `fee = price * fee_bps / 10000`. If `price = 3`, `fee_bps = 250`, fee = 0.

**Impact**: Zero-fee trades on micro-transactions.

**Countermeasure**: `fee = max(1, price * fee_bps / 10000)`. Or enforce minimum listing price.

### 2.4 [MEDIUM] copies_minted Unbounded Growth (max_copies=0)

**Scenario**: Unlimited minting with max_copies=0. copies_minted grows forever.

**Impact**: Low practical risk (u64::MAX unreachable).

**Countermeasure**: Document behavior. No code change needed.

---

## 3. OBJECT MANIPULATION

### 3.1 [CRITICAL] BPC Zombie: uses_remaining=0 Never Destroyed

**Scenario**: `use_bpc` decrements uses but caller must separately call `destroy_bpc`. If caller doesn't, zombie BPC persists.

**Impact**: Object pollution, potential logic bugs if code checks existence.

**Countermeasure**: Single function: `use_bpc(bpc: BlueprintCopy) -> Option<BlueprintCopy>`. Returns `None` (destroyed) at 0 uses, `Some(bpc)` otherwise.

### 3.2 [HIGH] Orphaned LeaseAgreement

**Scenario**: If LeaseAgreement is owned by lessee and lessee disappears, lessor cannot access it to call `forfeit_lease`. BPO permanently locked.

**Impact**: Permanent BPO loss.

**Countermeasure**: `LeaseAgreement` MUST be shared object. Both lessor and lessee can call their respective functions.

### 3.3 [HIGH] WorkOrder Stuck with Infinite Deadline

**Scenario**: Deadline set to u64::MAX. Acceptor disappears. Escrow locked forever (cancel_expired_order can never trigger).

**Impact**: Permanent escrow lock.

**Countermeasure**: `assert!(deadline <= clock::timestamp_ms(clock) + MAX_DEADLINE_MS)` where MAX_DEADLINE_MS = 30 days.

### 3.4 [MEDIUM] WorkOrderBoard vector<ID> Unbounded Growth

**Scenario**: open_orders vector grows without bound as orders accumulate.

**Impact**: Gas costs spike, board becomes unusable.

**Countermeasure**: Use `LinkedTable<ID, bool>` or `Table<ID, bool>` instead of `vector<ID>`.

---

## 4. ECONOMIC EXPLOITS

### 4.1 [CRITICAL] Free Production via Empty Recipe Inputs

**Scenario**: `create_recipe` with `inputs: []` and non-zero output. Infinite item minting from nothing.

**Impact**: Complete economic collapse.

**Countermeasure**:
```move
assert!(vector::length(&inputs) > 0, E_RECIPE_NO_INPUTS);
assert!(output.quantity > 0, E_RECIPE_ZERO_OUTPUT);
```
Consider admin-gated recipe creation.

### 4.2 [HIGH] Marketplace Fee Evasion via Direct Transfer

**Scenario**: Players use `transfer::public_transfer` to trade BPO/BPC directly, bypassing marketplace fees.

**Impact**: Zero fee collection.

**Countermeasure**: Accept as inherent (marketplace = convenience) or remove `store` ability / use Kiosk + Transfer Policy.

### 4.3 [HIGH] auto_complete Delivery Gaming

**Scenario**: Acceptor delivers matching item_type_id and quantity but no actual items transferred on-chain. Waits 72h, auto-completes, gets paid.

**Impact**: Payment without real delivery.

**Countermeasure**: Delivery must involve actual on-chain material transfer (not just counter increment). Or add dispute mechanism.

### 4.4 [MEDIUM] Dust Attack on WorkOrder

**Scenario**: Thousands of 1-MIST escrow orders pollute the board.

**Impact**: Board bloat, legitimate orders hidden.

**Countermeasure**: Enforce minimum escrow: `assert!(coin::value(&reward_coin) >= MIN_ORDER_REWARD)`.

---

## 5. ORDERING/TIMING ATTACKS

### 5.1 [HIGH] Front-Running Trigger Execution

**Scenario**: Adversary operator sees watcher's trigger tx in mempool, front-runs to execute at suboptimal time.

**Impact**: Sabotaged production timing.

**Countermeasure**: Limit to one operator per line, or accept as inherent multi-operator risk.

### 5.2 [HIGH] Tight Deadline Griefing

**Scenario**: Create order with tight deadline, wait for acceptance. After deadline: 90% refund to issuer, acceptor wasted effort for 10%.

**Impact**: Griefing acceptors.

**Countermeasure**: Compensation scales with delivery progress. Enforce minimum deadline (1 hour).

### 5.3 [MEDIUM] auto_complete 72h Clock Ambiguity

**Scenario**: No `last_delivery_timestamp` field. 72h clock start is undefined. Acceptor can game the timing.

**Impact**: Bypasses 72h grace period.

**Countermeasure**: Add `last_full_delivery_timestamp: u64`. Clock starts when `quantity_delivered >= quantity_requested`.

### 5.4 [MEDIUM] Cascading Trigger After Production Complete

**Scenario**: Precisely timed `complete_production` immediately triggers another auto-start via TriggerRule.

**Impact**: Uncontrolled production cascading.

**Countermeasure**: Minimum idle time between productions or per-trigger cooldown (already in spec).

---

## 6. DOS VECTORS

### 6.1 [CRITICAL] Bag Key Pollution in Buffers

**Scenario**: Attacker deposits 1 unit of thousands of different item_type_ids. Bag grows unboundedly.

**Impact**: Production gas costs spike, line unusable.

**Countermeasure**: Auth on deposit (owner-only). Validate item_type_id against recipe inputs. Limit max unique item types.

### 6.2 [HIGH] authorized_operators Vector Unbounded

**Scenario**: No size limit or dedup on operator list. Linear scan on every auth check.

**Impact**: Auth check gas grows linearly.

**Countermeasure**: Use `VecSet<address>`. Max 10 operators.

### 6.3 [HIGH] WorkOrder Spam on Shared Board

**Scenario**: Thousands of minimal orders flood open_orders vector.

**Impact**: Board becomes gas bomb.

**Countermeasure**: `Table` instead of `vector`. Minimum escrow. Rate-limit per address.

### 6.4 [MEDIUM] TriggerRule Spam

**Scenario**: Anyone creates thousands of rules pointing to one line. Watcher must evaluate all.

**Impact**: Watcher resource exhaustion.

**Countermeasure**: `create_trigger_rule` requires `&ProductionLine` + owner check. Store rules inside ProductionLine with max cap (10).

---

## Summary

| Category | Critical | High | Medium | Total |
|----------|----------|------|--------|-------|
| Access Control | 1 | 2 | 1 | 4 |
| Integer/Arithmetic | 1 | 2 | 1 | 4 |
| Object Manipulation | 1 | 2 | 1 | 4 |
| Economic Exploits | 1 | 2 | 1 | 4 |
| Ordering/Timing | 0 | 2 | 2 | 4 |
| DoS Vectors | 1 | 2 | 1 | 4 |
| **Total** | **5** | **12** | **7** | **24** |

## Top 5 Must-Fix Before Implementation

1. **Material efficiency rounding to zero** (2.1) -- ceiling division or minimum 1
2. **Free production via empty recipe** (4.1) -- assert inputs non-empty
3. **BPC zombie objects** (3.1) -- use-and-destroy in single function
4. **LeaseAgreement must be shared** (3.2) -- or BPO permanently lost
5. **Bag pollution in buffers** (6.1) -- auth on deposit + validate against recipe

## Implementation Checklist

- [ ] Every mutating function on ProductionLine checks auth
- [ ] Material efficiency uses ceiling division, asserts >= 1
- [ ] BPC use_and_destroy is a single atomic function
- [ ] LeaseAgreement is shared object
- [ ] Recipe creation requires non-empty inputs
- [ ] WorkOrder deadline has maximum cap
- [ ] Marketplace enforces minimum listing price
- [ ] WorkOrderBoard uses Table, not vector
- [ ] authorized_operators uses VecSet with max cap
- [ ] deposit_materials validates item_type_id against recipe
- [ ] TriggerRule creation requires ProductionLine reference + owner check
- [ ] Fee calculation uses max(1, computed_fee)
- [ ] Minimum escrow for WorkOrder creation
- [ ] auto_complete tracks last_full_delivery_timestamp

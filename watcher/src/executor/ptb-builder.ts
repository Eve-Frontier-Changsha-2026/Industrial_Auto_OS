import { Transaction } from "@mysten/sui/transactions";

// ─── industrial_core::production_line ───────────

export function completeProduction(
  tx: Transaction,
  pkg: string,
  lineId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::production_line::complete_production`,
    arguments: [tx.object(lineId), tx.object(clockId)],
  });
  return tx;
}

export function withdrawOutput(
  tx: Transaction,
  pkg: string,
  lineId: string,
  itemTypeId: number,
  quantity: number,
): Transaction {
  tx.moveCall({
    target: `${pkg}::production_line::withdraw_output`,
    arguments: [
      tx.object(lineId),
      tx.pure.u32(itemTypeId),
      tx.pure.u64(quantity),
    ],
  });
  return tx;
}

export function startProduction(
  tx: Transaction,
  pkg: string,
  lineId: string,
  recipeId: string,
  blueprintId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::production_line::start_production`,
    arguments: [
      tx.object(lineId),
      tx.object(recipeId),
      tx.object(blueprintId),
      tx.object(clockId),
    ],
  });
  return tx;
}

// ─── industrial_core::trigger_engine ────────────

export function executeTrigger(
  tx: Transaction,
  pkg: string,
  ruleId: string,
  lineId: string,
  recipeId: string,
  blueprintId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::trigger_engine::execute_trigger`,
    arguments: [
      tx.object(ruleId),
      tx.object(lineId),
      tx.object(recipeId),
      tx.object(blueprintId),
      tx.object(clockId),
    ],
  });
  return tx;
}

// ─── work_order ─────────────────────────────────

export function acceptWorkOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::accept_work_order`,
    arguments: [tx.object(orderId)],
  });
  return tx;
}

export function deliverWorkOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
  itemTypeId: number,
  quantity: number,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::deliver_work_order`,
    arguments: [
      tx.object(orderId),
      tx.pure.u32(itemTypeId),
      tx.pure.u64(quantity),
      tx.object(clockId),
    ],
  });
  return tx;
}

export function completeWorkOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
  boardId: string,
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::complete_work_order`,
    arguments: [tx.object(orderId), tx.object(boardId)],
  });
  return tx;
}

export function autoCompleteWorkOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
  boardId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::auto_complete_work_order`,
    arguments: [
      tx.object(orderId),
      tx.object(boardId),
      tx.object(clockId),
    ],
  });
  return tx;
}

export function cancelExpiredOrder(
  tx: Transaction,
  pkg: string,
  orderId: string,
  boardId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::work_order::cancel_expired_order`,
    arguments: [
      tx.object(orderId),
      tx.object(boardId),
      tx.object(clockId),
    ],
  });
  return tx;
}

// ─── work_order::fleet_integration ──────────────

export function createOrderFromDamageReport(
  tx: Transaction,
  pkg: string,
  boardId: string,
  description: string,
  recipeId: string,
  quantity: number,
  paymentCoinId: string,
  deadline: number,
  sourceEvent: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::fleet_integration::create_order_from_damage_report`,
    arguments: [
      tx.object(boardId),
      tx.pure.string(description),
      tx.pure.id(recipeId),
      tx.pure.u64(quantity),
      tx.object(paymentCoinId),
      tx.pure.u64(deadline),
      tx.pure.string(sourceEvent),
      tx.object(clockId),
    ],
  });
  return tx;
}

// ─── marketplace::lease ─────────────────────────

export function forfeitLease(
  tx: Transaction,
  pkg: string,
  leaseId: string,
  clockId: string = "0x6",
): Transaction {
  tx.moveCall({
    target: `${pkg}::lease::forfeit_lease`,
    arguments: [tx.object(leaseId), tx.object(clockId)],
  });
  return tx;
}

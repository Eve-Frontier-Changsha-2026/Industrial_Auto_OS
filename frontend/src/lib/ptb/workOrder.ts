import { Transaction } from "@mysten/sui/transactions";
import { CLOCK_ID } from "../constants";

export function buildCreateWorkOrder(
  pkg: string, boardId: string, description: string, recipeId: string,
  quantity: number, escrowAmount: bigint, deadline: number, priority: number,
): Transaction {
  const tx = new Transaction();
  const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(escrowAmount)]);
  tx.moveCall({
    target: `${pkg}::work_order::create_work_order`,
    arguments: [
      tx.object(boardId), tx.pure.string(description), tx.pure.id(recipeId),
      tx.pure.u64(quantity), paymentCoin, tx.pure.u64(deadline),
      tx.pure.u8(priority), tx.object(CLOCK_ID),
    ],
  });
  return tx;
}

export function buildCreateOrderFromDamageReport(
  pkg: string, boardId: string, description: string, recipeId: string,
  quantity: number, escrowAmount: bigint, deadline: number, sourceEvent: string,
): Transaction {
  const tx = new Transaction();
  const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(escrowAmount)]);
  tx.moveCall({
    target: `${pkg}::fleet_integration::create_order_from_damage_report`,
    arguments: [
      tx.object(boardId), tx.pure.string(description), tx.pure.id(recipeId),
      tx.pure.u64(quantity), paymentCoin, tx.pure.u64(deadline),
      tx.pure.string(sourceEvent), tx.object(CLOCK_ID),
    ],
  });
  return tx;
}

export function buildAcceptWorkOrder(pkg: string, orderId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({ target: `${pkg}::work_order::accept_work_order`, arguments: [tx.object(orderId)] });
  return tx;
}

export function buildDeliverWorkOrder(pkg: string, orderId: string, itemTypeId: number, quantity: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::deliver_work_order`,
    arguments: [tx.object(orderId), tx.pure.u32(itemTypeId), tx.pure.u64(quantity), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildCompleteWorkOrder(pkg: string, orderId: string, boardId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::complete_work_order`,
    arguments: [tx.object(orderId), tx.object(boardId)],
  });
  return tx;
}

export function buildAutoCompleteWorkOrder(pkg: string, orderId: string, boardId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::auto_complete_work_order`,
    arguments: [tx.object(orderId), tx.object(boardId), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildCancelWorkOrder(pkg: string, orderId: string, boardId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::cancel_work_order`,
    arguments: [tx.object(orderId), tx.object(boardId)],
  });
  return tx;
}

export function buildCancelExpiredOrder(pkg: string, orderId: string, boardId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::work_order::cancel_expired_order`,
    arguments: [tx.object(orderId), tx.object(boardId), tx.object(CLOCK_ID)],
  });
  return tx;
}

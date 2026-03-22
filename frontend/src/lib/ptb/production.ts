import { Transaction } from "@mysten/sui/transactions";
import { CLOCK_ID } from "../constants";

export function buildStartProduction(pkg: string, lineId: string, recipeId: string, bpoId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::start_production`,
    arguments: [tx.object(lineId), tx.object(recipeId), tx.object(bpoId), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildCompleteProduction(pkg: string, lineId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::complete_production`,
    arguments: [tx.object(lineId), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildDepositMaterials(pkg: string, lineId: string, recipeId: string, itemTypeId: number, quantity: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::deposit_materials`,
    arguments: [tx.object(lineId), tx.object(recipeId), tx.pure.u32(itemTypeId), tx.pure.u64(quantity)],
  });
  return tx;
}

export function buildDepositFuel(pkg: string, lineId: string, amount: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::deposit_fuel`,
    arguments: [tx.object(lineId), tx.pure.u64(amount)],
  });
  return tx;
}

export function buildWithdrawOutput(pkg: string, lineId: string, itemTypeId: number, quantity: number): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::withdraw_output`,
    arguments: [tx.object(lineId), tx.pure.u32(itemTypeId), tx.pure.u64(quantity)],
  });
  return tx;
}

export function buildAuthorizeOperator(pkg: string, lineId: string, operator: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::authorize_operator`,
    arguments: [tx.object(lineId), tx.pure.address(operator)],
  });
  return tx;
}

export function buildRevokeOperator(pkg: string, lineId: string, operator: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::production_line::revoke_operator`,
    arguments: [tx.object(lineId), tx.pure.address(operator)],
  });
  return tx;
}

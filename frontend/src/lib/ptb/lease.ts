import { Transaction } from "@mysten/sui/transactions";
import { CLOCK_ID } from "../constants";

export function buildCreateLease(
  pkg: string, bpoId: string, lessee: string,
  depositAmount: bigint, expiry: number, dailyRate: number,
): Transaction {
  const tx = new Transaction();
  const [depositCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(depositAmount)]);
  tx.moveCall({
    target: `${pkg}::lease::create_lease`,
    arguments: [
      tx.object(bpoId), tx.pure.address(lessee), depositCoin,
      tx.pure.u64(expiry), tx.pure.u64(dailyRate),
    ],
  });
  return tx;
}

export function buildReturnLease(pkg: string, leaseId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::lease::return_lease`,
    arguments: [tx.object(leaseId)],
  });
  return tx;
}

export function buildForfeitLease(pkg: string, leaseId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::lease::forfeit_lease`,
    arguments: [tx.object(leaseId), tx.object(CLOCK_ID)],
  });
  return tx;
}

export function buildStartProductionWithLease(
  marketplacePkg: string, leaseId: string,
  lineId: string, recipeId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${marketplacePkg}::lease::start_production_with_lease`,
    arguments: [
      tx.object(leaseId), tx.object(lineId),
      tx.object(recipeId), tx.object(CLOCK_ID),
    ],
  });
  return tx;
}

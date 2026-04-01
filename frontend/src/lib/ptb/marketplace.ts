import { Transaction } from "@mysten/sui/transactions";

export function buildListBpo(pkg: string, marketId: string, bpoId: string, price: bigint): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::marketplace::list_bpo`,
    arguments: [tx.object(marketId), tx.object(bpoId), tx.pure.u64(price)],
  });
  return tx;
}

export function buildDelistBpo(pkg: string, listingId: string, sender: string): Transaction {
  const tx = new Transaction();
  const bpo = tx.moveCall({
    target: `${pkg}::marketplace::delist_bpo`,
    arguments: [tx.object(listingId)],
  });
  tx.transferObjects([bpo], sender);
  return tx;
}

export function buildBuyBpo(pkg: string, marketId: string, listingId: string, price: bigint): Transaction {
  const tx = new Transaction();
  const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(price)]);
  tx.moveCall({
    target: `${pkg}::marketplace::buy_bpo`,
    arguments: [tx.object(marketId), tx.object(listingId), paymentCoin],
  });
  return tx;
}

export function buildListBpc(pkg: string, marketId: string, bpcId: string, price: bigint): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::marketplace::list_bpc`,
    arguments: [tx.object(marketId), tx.object(bpcId), tx.pure.u64(price)],
  });
  return tx;
}

export function buildDelistBpc(pkg: string, listingId: string, sender: string): Transaction {
  const tx = new Transaction();
  const bpc = tx.moveCall({
    target: `${pkg}::marketplace::delist_bpc`,
    arguments: [tx.object(listingId)],
  });
  tx.transferObjects([bpc], sender);
  return tx;
}

export function buildBuyBpc(pkg: string, marketId: string, listingId: string, price: bigint): Transaction {
  const tx = new Transaction();
  const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(price)]);
  tx.moveCall({
    target: `${pkg}::marketplace::buy_bpc`,
    arguments: [tx.object(marketId), tx.object(listingId), paymentCoin],
  });
  return tx;
}

import { Transaction } from "@mysten/sui/transactions";

export function buildMintBpc(pkg: string, bpoId: string, uses: number, sender: string): Transaction {
  const tx = new Transaction();
  const bpc = tx.moveCall({
    target: `${pkg}::blueprint::mint_bpc`,
    arguments: [tx.object(bpoId), tx.pure.u64(uses)],
  });
  tx.transferObjects([bpc], sender);
  return tx;
}

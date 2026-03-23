import { Transaction } from "@mysten/sui/transactions";
import { CLOCK_ID } from "../constants";

export function buildClaimFromBlueprint(
  pkg: string, accessRegistryId: string,
  bpoId: string, lineId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::factory_access::claim_from_blueprint`,
    arguments: [
      tx.object(accessRegistryId),
      tx.object(bpoId),
      tx.object(lineId),
    ],
  });
  return tx;
}

export function buildClaimFromLease(
  pkg: string, accessRegistryId: string,
  leaseId: string, lineId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::factory_access::claim_from_lease`,
    arguments: [
      tx.object(accessRegistryId),
      tx.object(leaseId),
      tx.object(lineId),
    ],
  });
  return tx;
}

export function buildClaimFromWorkOrder(
  pkg: string, accessRegistryId: string,
  woId: string, lineId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::factory_access::claim_from_work_order`,
    arguments: [
      tx.object(accessRegistryId),
      tx.object(woId),
      tx.object(lineId),
    ],
  });
  return tx;
}

export function buildSurrenderPass(
  pkg: string, accessRegistryId: string, passId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::factory_access::surrender_pass`,
    arguments: [
      tx.object(accessRegistryId),
      tx.object(passId),
    ],
  });
  return tx;
}

export function buildRevokeExpired(
  pkg: string, accessRegistryId: string, passId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::factory_access::revoke_expired`,
    arguments: [
      tx.object(accessRegistryId),
      tx.object(passId),
      tx.object(CLOCK_ID),
    ],
  });
  return tx;
}

export function buildAdminRevokePass(
  pkg: string, accessRegistryId: string,
  passId: string, holder: string, lineId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::factory_access::admin_revoke_pass`,
    arguments: [
      tx.object(accessRegistryId),
      tx.pure.id(passId),
      tx.pure.address(holder),
      tx.object(lineId),
    ],
  });
  return tx;
}

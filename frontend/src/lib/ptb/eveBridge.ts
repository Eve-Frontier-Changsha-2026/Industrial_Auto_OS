import { Transaction } from "@mysten/sui/transactions";

export function buildAddGlobalMapping(
  pkg: string, registryId: string, adminCapId: string,
  eveTypeId: string, materialId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::eve_bridge::add_global_mapping`,
    arguments: [
      tx.object(registryId),
      tx.object(adminCapId),
      tx.pure.u64(eveTypeId),
      tx.pure.string(materialId),
    ],
  });
  return tx;
}

export function buildRemoveGlobalMapping(
  pkg: string, registryId: string, adminCapId: string,
  eveTypeId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::eve_bridge::remove_global_mapping`,
    arguments: [
      tx.object(registryId),
      tx.object(adminCapId),
      tx.pure.u64(eveTypeId),
    ],
  });
  return tx;
}

export function buildDisableFactoryMapping(
  pkg: string, registryId: string, lineId: string,
  eveTypeId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::eve_bridge::disable_factory_mapping`,
    arguments: [
      tx.object(registryId),
      tx.object(lineId),
      tx.pure.u64(eveTypeId),
    ],
  });
  return tx;
}

export function buildEnableFactoryMapping(
  pkg: string, registryId: string, lineId: string,
  eveTypeId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::eve_bridge::enable_factory_mapping`,
    arguments: [
      tx.object(registryId),
      tx.object(lineId),
      tx.pure.u64(eveTypeId),
    ],
  });
  return tx;
}

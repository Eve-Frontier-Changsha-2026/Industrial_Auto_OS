import { Transaction } from "@mysten/sui/transactions";

export function buildCreateTriggerRule(
  pkg: string, lineId: string, conditionType: number, threshold: number,
  targetItemTypeId: number, autoRepeat: boolean, cooldownMs: number,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::trigger_engine::create_trigger_rule`,
    arguments: [
      tx.object(lineId), tx.pure.u8(conditionType), tx.pure.u64(threshold),
      tx.pure.u32(targetItemTypeId), tx.pure.bool(autoRepeat), tx.pure.u64(cooldownMs),
    ],
  });
  return tx;
}

export function buildToggleTrigger(pkg: string, ruleId: string, enabled: boolean): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${pkg}::trigger_engine::toggle_trigger`,
    arguments: [tx.object(ruleId), tx.pure.bool(enabled)],
  });
  return tx;
}

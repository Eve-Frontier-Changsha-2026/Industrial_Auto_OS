import { useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS, TYPE_STRINGS } from "../lib/constants";
import type { TriggerRule } from "../lib/types";

export function useTriggers() {
  const client = useSuiClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ["triggers", account?.address],
    queryFn: async (): Promise<TriggerRule[]> => {
      if (!account) return [];
      const { data } = await client.getOwnedObjects({
        owner: account.address,
        filter: {
          StructType: TYPE_STRINGS.TriggerRule(PACKAGE_IDS.industrial_core),
        },
        options: { showContent: true },
      });
      return data.map((item) => {
        const f = (item.data!.content as any).fields;
        return {
          id: item.data!.objectId,
          productionLineId: f.production_line_id,
          conditionType: Number(f.condition_type),
          threshold: Number(f.threshold),
          targetItemTypeId: Number(f.target_item_type_id),
          enabled: f.enabled,
          lastTriggered: Number(f.last_triggered),
          cooldownMs: Number(f.cooldown_ms),
          autoRepeat: f.auto_repeat,
        };
      });
    },
    refetchInterval: 5000,
  });
}

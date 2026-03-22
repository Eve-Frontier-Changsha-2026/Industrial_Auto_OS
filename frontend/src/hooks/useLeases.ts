import { useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS } from "../lib/constants";
import type { LeaseAgreement } from "../lib/types";

export function useLeases() {
  const client = useSuiClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ["leases", account?.address],
    queryFn: async (): Promise<LeaseAgreement[]> => {
      if (!account) return [];
      const { data: events } = await client.queryEvents({
        query: {
          MoveEventType: `${PACKAGE_IDS.marketplace}::lease::LeaseCreated`,
        },
        order: "descending",
        limit: 50,
      });

      const leaseIds = events
        .map((e) => (e.parsedJson as any).lease_id)
        .filter(Boolean);
      if (!leaseIds.length) return [];

      const objects = await client.multiGetObjects({
        ids: [...new Set(leaseIds)],
        options: { showContent: true },
      });

      return objects
        .filter((o) => o.data?.content?.dataType === "moveObject")
        .map((o) => {
          const f = (o.data!.content as any).fields;
          return {
            id: o.data!.objectId,
            lessor: f.lessor,
            lessee: f.lessee,
            expiry: Number(f.expiry),
            dailyRate: Number(f.daily_rate),
            depositValue: Number(f.deposit_value),
            active: f.active,
          };
        })
        .filter(
          (l) =>
            l.lessor === account.address || l.lessee === account.address,
        );
    },
    refetchInterval: 10000,
  });
}

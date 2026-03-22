import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS } from "../lib/constants";
import type { BpoListing, BpcListing } from "../lib/types";

export function useMarketplace() {
  const client = useSuiClient();

  const bpoListings = useQuery({
    queryKey: ["market-bpo-listings"],
    queryFn: async (): Promise<BpoListing[]> => {
      const { data: events } = await client.queryEvents({
        query: {
          MoveEventType: `${PACKAGE_IDS.marketplace}::marketplace::BpoListed`,
        },
        order: "descending",
        limit: 50,
      });

      const listingIds = events
        .map((e) => (e.parsedJson as any).listing_id)
        .filter(Boolean);
      if (!listingIds.length) return [];

      const objects = await client.multiGetObjects({
        ids: [...new Set(listingIds)],
        options: { showContent: true },
      });

      return objects
        .filter((o) => o.data?.content?.dataType === "moveObject")
        .map((o) => {
          const f = (o.data!.content as any).fields;
          return {
            id: o.data!.objectId,
            seller: f.seller,
            price: Number(f.price),
            active: f.active,
            bpoId: f.bpo_id ?? o.data!.objectId,
          };
        })
        .filter((l) => l.active);
    },
    refetchInterval: 10000,
  });

  const bpcListings = useQuery({
    queryKey: ["market-bpc-listings"],
    queryFn: async (): Promise<BpcListing[]> => {
      const { data: events } = await client.queryEvents({
        query: {
          MoveEventType: `${PACKAGE_IDS.marketplace}::marketplace::BpcListed`,
        },
        order: "descending",
        limit: 50,
      });

      const listingIds = events
        .map((e) => (e.parsedJson as any).listing_id)
        .filter(Boolean);
      if (!listingIds.length) return [];

      const objects = await client.multiGetObjects({
        ids: [...new Set(listingIds)],
        options: { showContent: true },
      });

      return objects
        .filter((o) => o.data?.content?.dataType === "moveObject")
        .map((o) => {
          const f = (o.data!.content as any).fields;
          return {
            id: o.data!.objectId,
            seller: f.seller,
            price: Number(f.price),
            active: f.active,
            bpcId: f.bpc_id ?? o.data!.objectId,
          };
        })
        .filter((l) => l.active);
    },
    refetchInterval: 10000,
  });

  return { bpoListings, bpcListings };
}

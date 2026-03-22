import { useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS, TYPE_STRINGS } from "../lib/constants";
import type { BlueprintOriginal, BlueprintCopy } from "../lib/types";

export function useBlueprints() {
  const client = useSuiClient();
  const account = useCurrentAccount();

  const bpoQuery = useQuery({
    queryKey: ["bpos", account?.address],
    queryFn: async (): Promise<BlueprintOriginal[]> => {
      if (!account) return [];
      const { data } = await client.getOwnedObjects({
        owner: account.address,
        filter: {
          StructType: TYPE_STRINGS.BlueprintOriginal(
            PACKAGE_IDS.industrial_core,
          ),
        },
        options: { showContent: true },
      });
      return data.map((item) => {
        const f = (item.data!.content as any).fields;
        return {
          id: item.data!.objectId,
          recipeId: f.recipe_id,
          copiesMinted: Number(f.copies_minted),
          maxCopies: Number(f.max_copies),
          materialEfficiency: Number(f.material_efficiency),
          timeEfficiency: Number(f.time_efficiency),
        };
      });
    },
    refetchInterval: 10000,
  });

  const bpcQuery = useQuery({
    queryKey: ["bpcs", account?.address],
    queryFn: async (): Promise<BlueprintCopy[]> => {
      if (!account) return [];
      const { data } = await client.getOwnedObjects({
        owner: account.address,
        filter: {
          StructType: TYPE_STRINGS.BlueprintCopy(PACKAGE_IDS.industrial_core),
        },
        options: { showContent: true },
      });
      return data.map((item) => {
        const f = (item.data!.content as any).fields;
        return {
          id: item.data!.objectId,
          recipeId: f.recipe_id,
          sourceBpoId: f.source_bpo_id,
          usesRemaining: Number(f.uses_remaining),
          materialEfficiency: Number(f.material_efficiency),
          timeEfficiency: Number(f.time_efficiency),
        };
      });
    },
    refetchInterval: 10000,
  });

  return { bpos: bpoQuery, bpcs: bpcQuery };
}

import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import type { Recipe } from "../lib/types";

const RECIPE_IDS = (import.meta.env.VITE_RECIPE_IDS ?? "")
  .split(",")
  .filter(Boolean);

export function useRecipes() {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["recipes", RECIPE_IDS],
    queryFn: async (): Promise<Recipe[]> => {
      if (!RECIPE_IDS.length) return [];
      const results = await client.multiGetObjects({
        ids: RECIPE_IDS,
        options: { showContent: true },
      });
      return results
        .filter((r) => r.data?.content?.dataType === "moveObject")
        .map((r) => {
          const fields = (r.data!.content as any).fields;
          return {
            id: r.data!.objectId,
            name: fields.name,
            inputs: (fields.inputs ?? []).map((inp: any) => ({
              itemTypeId: Number(inp.fields.item_type_id),
              quantity: Number(inp.fields.quantity),
            })),
            output: {
              itemTypeId: Number(fields.output.fields.item_type_id),
              quantity: Number(fields.output.fields.quantity),
            },
            baseDurationMs: Number(fields.base_duration_ms),
            energyCost: Number(fields.energy_cost),
            creator: fields.creator,
          } satisfies Recipe;
        });
    },
    refetchInterval: 30000,
  });
}

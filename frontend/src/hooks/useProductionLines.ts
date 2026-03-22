import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import type { ProductionLine } from "../lib/types";

export function useProductionLines(lineIds: string[]) {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["production-lines", lineIds],
    queryFn: async (): Promise<ProductionLine[]> => {
      if (!lineIds.length) return [];
      const results = await client.multiGetObjects({
        ids: lineIds,
        options: { showContent: true },
      });
      return results
        .filter((r) => r.data?.content?.dataType === "moveObject")
        .map((r) => {
          const fields = (r.data!.content as any).fields;
          return {
            id: r.data!.objectId,
            owner: fields.owner,
            name: fields.name,
            status: Number(fields.status),
            recipeId: fields.recipe_id,
            fuelReserve: Number(fields.fuel_reserve),
            jobsCompleted: Number(fields.jobs_completed),
            currentJobEnd: Number(fields.current_job_end),
            operators: fields.operators ?? [],
          } satisfies ProductionLine;
        });
    },
    refetchInterval: 5000,
    enabled: lineIds.length > 0,
  });
}

import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { SHARED_OBJECTS } from "../lib/constants";
import type { WorkOrder } from "../lib/types";

export function useWorkOrders() {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["work-orders"],
    queryFn: async (): Promise<WorkOrder[]> => {
      const { data: fields } = await client.getDynamicFields({
        parentId: SHARED_OBJECTS.work_order_board,
      });

      if (!fields.length) return [];

      const ids = fields.map((f) => f.objectId);
      const objects = await client.multiGetObjects({
        ids,
        options: { showContent: true },
      });

      return objects
        .filter((o) => o.data?.content?.dataType === "moveObject")
        .map((o) => {
          const f = (o.data!.content as any).fields;
          return {
            id: o.data!.objectId,
            issuer: f.issuer,
            description: f.description,
            recipeId: f.recipe_id,
            quantityRequired: Number(f.quantity_required),
            quantityDelivered: Number(f.quantity_delivered),
            escrowValue: Number(f.escrow_value),
            deadline: Number(f.deadline),
            status: Number(f.status),
            acceptor: f.acceptor?.fields?.vec?.[0] ?? null,
            priority: Number(f.priority),
            sourceEvent: f.source_event?.fields?.vec?.[0] ?? null,
            deliveredAt: f.delivered_at?.fields?.vec?.[0]
              ? Number(f.delivered_at.fields.vec[0])
              : null,
          } satisfies WorkOrder;
        });
    },
    refetchInterval: 5000,
  });
}

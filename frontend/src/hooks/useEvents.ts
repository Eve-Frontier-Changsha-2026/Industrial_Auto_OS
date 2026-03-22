import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { PACKAGE_IDS } from "../lib/constants";

export interface ChainEvent {
  id: string;
  type: string;
  timestamp: number;
  parsedJson: Record<string, any>;
}

const EVENT_TYPES = [
  `${PACKAGE_IDS.industrial_core}::production_line::ProductionStartedEvent`,
  `${PACKAGE_IDS.industrial_core}::production_line::ProductionCompletedEvent`,
  `${PACKAGE_IDS.industrial_core}::trigger_engine::TriggerFiredEvent`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderCreated`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderAccepted`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderDelivered`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderCompleted`,
  `${PACKAGE_IDS.work_order}::work_order::WorkOrderCancelled`,
  `${PACKAGE_IDS.marketplace}::marketplace::BpoListed`,
  `${PACKAGE_IDS.marketplace}::marketplace::BpoSold`,
  `${PACKAGE_IDS.marketplace}::marketplace::BpcListed`,
  `${PACKAGE_IDS.marketplace}::marketplace::BpcSold`,
  `${PACKAGE_IDS.marketplace}::lease::LeaseCreated`,
  `${PACKAGE_IDS.marketplace}::lease::LeaseReturned`,
  `${PACKAGE_IDS.marketplace}::lease::LeaseForfeited`,
];

export function useEvents(limit = 50) {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["events", limit],
    queryFn: async (): Promise<ChainEvent[]> => {
      const results = await Promise.allSettled(
        EVENT_TYPES.map(async (eventType) => {
          const { data } = await client.queryEvents({
            query: { MoveEventType: eventType },
            order: "descending",
            limit: 10,
          });
          return data.map((e) => ({
            id: e.id.txDigest + "-" + e.id.eventSeq,
            type: eventType.split("::").pop() ?? "",
            timestamp: Number(e.timestampMs ?? 0),
            parsedJson: e.parsedJson as Record<string, any>,
          }));
        }),
      );

      const allEvents: ChainEvent[] = results
        .filter(
          (r): r is PromiseFulfilledResult<ChainEvent[]> =>
            r.status === "fulfilled",
        )
        .flatMap((r) => r.value);

      return allEvents.sort((a, b) => b.timestamp - a.timestamp).slice(0, limit);
    },
    refetchInterval: 3000,
  });
}

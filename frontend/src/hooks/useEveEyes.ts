import { useQuery } from "@tanstack/react-query";
import {
  fetchKillmails,
  fetchBuildingLeaderboard,
  fetchTransactionBlocks,
  fetchMoveCallsForTx,
  fetchMoveCallDetail,
  type Killmail,
  type LeaderboardEntry,
  type TransactionBlock,
  type MoveCallItem,
  type PaginatedResponse,
} from "../lib/eveEyes";

export function useKillmails(params?: { limit?: number; status?: string }) {
  return useQuery({
    queryKey: ["eve-eyes-killmails", params],
    queryFn: (): Promise<{ items: Killmail[] }> => fetchKillmails(params),
    refetchInterval: 10_000,
    retry: 1,
    staleTime: 5_000,
  });
}

export function useBuildingLeaderboard(params?: {
  limit?: number;
  moduleName?: string;
}) {
  return useQuery({
    queryKey: ["eve-eyes-leaderboard", params],
    queryFn: (): Promise<{ leaderboard: LeaderboardEntry[] }> =>
      fetchBuildingLeaderboard(params),
    refetchInterval: 30_000,
    retry: 1,
    staleTime: 10_000,
  });
}

export function useTransactionBlocks(params: {
  page?: number;
  pageSize?: number;
  senderAddress?: string;
  status?: string;
  digest?: string;
}) {
  return useQuery({
    queryKey: ["eve-eyes-tx-blocks", params],
    queryFn: (): Promise<PaginatedResponse<TransactionBlock>> =>
      fetchTransactionBlocks(params),
    retry: 1,
    staleTime: 5_000,
  });
}

export function useMoveCallsForTx(digest: string | null) {
  return useQuery({
    queryKey: ["eve-eyes-move-calls-tx", digest],
    queryFn: (): Promise<{ items: MoveCallItem[] }> =>
      fetchMoveCallsForTx(digest!),
    enabled: !!digest,
    retry: 1,
    staleTime: 60_000,
  });
}

export function useMoveCallDetail(
  txDigest: string | null,
  callIndex: number | null,
) {
  return useQuery({
    queryKey: ["eve-eyes-move-call-detail", txDigest, callIndex],
    queryFn: (): Promise<{ item: MoveCallItem }> =>
      fetchMoveCallDetail(txDigest!, callIndex!),
    enabled: !!txDigest && callIndex !== null,
    retry: 1,
    staleTime: 60_000,
  });
}

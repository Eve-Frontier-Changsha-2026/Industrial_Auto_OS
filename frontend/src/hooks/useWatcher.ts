import { useQuery } from "@tanstack/react-query";
import { WATCHER_URL } from "../lib/constants";

export interface WatcherRule {
  name: string;
  description: string;
  enabled: boolean;
}

export interface WatcherTx {
  rule_name: string;
  tx_digest: string;
  status: string;
  error?: string;
  gas_used: number;
  created_at: number;
}

export function useWatcherStatus() {
  return useQuery({
    queryKey: ["watcher-status"],
    queryFn: async (): Promise<{ rules: WatcherRule[] }> => {
      const res = await fetch(`${WATCHER_URL}/status`);
      if (!res.ok) throw new Error(`Watcher API: ${res.status}`);
      return res.json();
    },
    refetchInterval: 5000,
  });
}

export function useWatcherHealth() {
  return useQuery({
    queryKey: ["watcher-health"],
    queryFn: async () => {
      const res = await fetch(`${WATCHER_URL}/health`);
      if (!res.ok) throw new Error(`Watcher API: ${res.status}`);
      return res.json();
    },
    refetchInterval: 10000,
  });
}

export function useWatcherTxLog(filters?: {
  status?: string;
  rule?: string;
  limit?: number;
}) {
  const params = new URLSearchParams();
  if (filters?.status) params.set("status", filters.status);
  if (filters?.rule) params.set("rule", filters.rule);
  if (filters?.limit) params.set("limit", String(filters.limit));

  return useQuery({
    queryKey: ["watcher-tx-log", filters],
    queryFn: async (): Promise<{ transactions: WatcherTx[] }> => {
      const res = await fetch(`${WATCHER_URL}/tx-log?${params}`);
      if (!res.ok) throw new Error(`Watcher API: ${res.status}`);
      return res.json();
    },
    refetchInterval: 5000,
  });
}

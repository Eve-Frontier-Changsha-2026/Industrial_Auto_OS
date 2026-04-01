import { EVE_EYES_URL, WATCHER_URL } from "./constants";

// ─── Types ──────────────────────────────────

export interface Killmail {
  killmailItemId: string;
  killTimestamp: string;
  killer: { label: string };
  victim: { label: string };
  status?: string;
}

export interface LeaderboardEntry {
  owner?: string;
  wallet?: string;
  count?: number;
  [key: string]: unknown;
}

export interface TransactionBlock {
  digest: string;
  sender?: string;
  status?: string;
  transactionKind?: string;
  transactionTime?: string;
  rawContent?: unknown;
  effects?: unknown;
  events?: unknown;
}

export interface MoveCallItem {
  packageId?: string;
  moduleName?: string;
  functionName?: string;
  callIndex?: number;
  actionSummary?: string;
  actionEntities?: unknown[];
  rawCall?: unknown;
}

export interface PaginatedResponse<T> {
  items: T[];
  pagination?: {
    page: number;
    pageSize: number;
    total?: number;
    hasMore?: boolean;
  };
}

// ─── Helpers ────────────────────────────────

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Eve Eyes API: ${res.status} ${res.statusText}`);
  }
  const data = await res.json();
  if (data === null || typeof data !== "object") {
    throw new Error("Eve Eyes API: unexpected response shape");
  }
  return data as T;
}

function qs(params: Record<string, string | number | undefined>): string {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== "") sp.set(k, String(v));
  }
  return sp.toString();
}

// ─── Public Endpoints (direct) ──────────────

export async function fetchKillmails(params?: {
  limit?: number;
  status?: string;
}): Promise<{ items: Killmail[] }> {
  const q = qs({ limit: params?.limit, status: params?.status });
  const data = await fetchJson<{ items?: unknown }>(`${EVE_EYES_URL}/api/indexer/killmails${q ? `?${q}` : ""}`);
  return { items: Array.isArray(data.items) ? data.items : [] };
}

export async function fetchBuildingLeaderboard(params?: {
  limit?: number;
  moduleName?: string;
}): Promise<{ leaderboard: LeaderboardEntry[] }> {
  const q = qs({ limit: params?.limit, moduleName: params?.moduleName });
  const data = await fetchJson<{ leaderboard?: unknown }>(`${EVE_EYES_URL}/api/v1/indexer/building-leaderboard${q ? `?${q}` : ""}`);
  return { leaderboard: Array.isArray(data.leaderboard) ? data.leaderboard : [] };
}

export function fetchTransactionBlockDetail(
  digest: string,
): Promise<{ item: TransactionBlock }> {
  return fetchJson(`${EVE_EYES_URL}/api/indexer/transaction-blocks/${encodeURIComponent(digest)}`);
}

export function fetchMoveCallsForTx(
  digest: string,
): Promise<{ items: MoveCallItem[] }> {
  return fetchJson(
    `${EVE_EYES_URL}/api/indexer/transaction-blocks/${encodeURIComponent(digest)}/move-calls?includeActionSummary=1`,
  );
}

export function fetchMoveCallDetail(
  txDigest: string,
  callIndex: number,
): Promise<{ item: MoveCallItem }> {
  return fetchJson(
    `${EVE_EYES_URL}/api/indexer/move-calls/${encodeURIComponent(txDigest)}/${callIndex}`,
  );
}

export function fetchModuleCallCounts(): Promise<{ modules: unknown[] }> {
  return fetchJson(`${EVE_EYES_URL}/api/indexer/module-call-counts`);
}

// ─── Proxied Endpoints (through watcher) ────

export async function fetchTransactionBlocks(params: {
  page?: number;
  pageSize?: number;
  senderAddress?: string;
  status?: string;
  digest?: string;
}): Promise<PaginatedResponse<TransactionBlock>> {
  const page = params.page ?? 1;
  // Page 1-3: direct to Eve Eyes (public). Page 4+: through watcher proxy.
  const base = page <= 3 ? EVE_EYES_URL + "/api/indexer" : WATCHER_URL + "/eve-eyes";
  const q = qs({
    page,
    pageSize: params.pageSize ?? 20,
    senderAddress: params.senderAddress,
    status: params.status,
    digest: params.digest,
  });
  const data = await fetchJson<{ items?: unknown; pagination?: unknown }>(`${base}/transaction-blocks?${q}`);
  return {
    items: Array.isArray(data.items) ? data.items : [],
    pagination: data.pagination as PaginatedResponse<TransactionBlock>["pagination"],
  };
}

export async function fetchMoveCalls(params: {
  page?: number;
  pageSize?: number;
  packageId?: string;
  moduleName?: string;
  functionName?: string;
}): Promise<PaginatedResponse<MoveCallItem>> {
  const page = params.page ?? 1;
  const base = page <= 3 ? EVE_EYES_URL + "/api/indexer" : WATCHER_URL + "/eve-eyes";
  const q = qs({
    page,
    pageSize: params.pageSize ?? 20,
    packageId: params.packageId,
    moduleName: params.moduleName,
    functionName: params.functionName,
  });
  const data = await fetchJson<{ items?: unknown; pagination?: unknown }>(`${base}/move-calls?${q}`);
  return {
    items: Array.isArray(data.items) ? data.items : [],
    pagination: data.pagination as PaginatedResponse<MoveCallItem>["pagination"],
  };
}

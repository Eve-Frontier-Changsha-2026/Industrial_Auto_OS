import { Router } from "express";
import type { EveEyesConfig } from "../types.js";

const TX_BLOCKS_ALLOWED = new Set([
  "page", "pageSize", "network", "senderAddress", "status",
  "digest", "transactionKind", "checkpoint",
]);

const MOVE_CALLS_ALLOWED = new Set([
  "page", "pageSize", "network", "senderAddress", "status",
  "txDigest", "packageId", "moduleName", "functionName",
  "callIndex", "includeActionSummary",
]);

function filterParams(
  raw: Record<string, unknown>,
  allowed: Set<string>,
): URLSearchParams {
  const params = new URLSearchParams();
  for (const [key, val] of Object.entries(raw)) {
    if (allowed.has(key) && typeof val === "string") {
      params.set(key, val);
    }
  }
  return params;
}

export function createEveEyesProxy(config: EveEyesConfig): Router {
  const router = Router();
  const apiKey =
    process.env.EVE_EYES_API_KEY ?? config.api_key;
  const baseUrl = config.base_url.replace(/\/$/, "");

  async function proxyGet(
    upstream: string,
    allowed: Set<string>,
    query: Record<string, unknown>,
    res: import("express").Response,
  ): Promise<void> {
    const params = filterParams(query, allowed);
    const url = `${baseUrl}${upstream}?${params}`;
    try {
      const upstream_res = await fetch(url, {
        headers: { Authorization: `ApiKey ${apiKey}` },
      });
      const body = await upstream_res.text();
      res.status(upstream_res.status).type("json").send(body);
    } catch (err) {
      res.status(502).json({
        error: "Eve Eyes API unavailable",
        detail: err instanceof Error ? err.message : String(err),
      });
    }
  }

  router.get("/transaction-blocks", (req, res) => {
    proxyGet(
      "/api/indexer/transaction-blocks",
      TX_BLOCKS_ALLOWED,
      req.query as Record<string, unknown>,
      res,
    );
  });

  router.get("/move-calls", (req, res) => {
    proxyGet(
      "/api/indexer/move-calls",
      MOVE_CALLS_ALLOWED,
      req.query as Record<string, unknown>,
      res,
    );
  });

  return router;
}

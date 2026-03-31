import { Router } from "express";
import type { Database } from "better-sqlite3";
import type { RuleRegistry } from "../rules/registry.js";
import { createEveEyesProxy } from "./eve-eyes-proxy.js";
import type { EveEyesConfig } from "../types.js";

const startTime = Date.now();
let lastPollTimestamp = Date.now();

export function updateLastPoll(): void {
  lastPollTimestamp = Date.now();
}

export function createApiRouter(
  db: Database,
  registry: RuleRegistry,
  eveEyesConfig?: EveEyesConfig,
): Router {
  const router = Router();

  router.get("/health", (_req, res) => {
    res.json({
      status: "ok",
      uptime_ms: Date.now() - startTime,
      last_poll: lastPollTimestamp,
    });
  });

  router.get("/status", (_req, res) => {
    const rules = registry.listAll().map((r) => ({
      name: r.name,
      description: r.description,
      enabled: r.enabled,
    }));
    res.json({ rules });
  });

  router.get("/tx-log", (req, res) => {
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const status = req.query.status as string | undefined;
    const ruleName = req.query.rule as string | undefined;

    let sql = "SELECT * FROM tx_log";
    const params: any[] = [];
    const conditions: string[] = [];

    if (status) {
      conditions.push("status = ?");
      params.push(status);
    }
    if (ruleName) {
      conditions.push("rule_name = ?");
      params.push(ruleName);
    }

    if (conditions.length) sql += " WHERE " + conditions.join(" AND ");
    sql += " ORDER BY id DESC LIMIT ?";
    params.push(limit);

    const transactions = db.prepare(sql).all(...params);
    res.json({ transactions, total: transactions.length });
  });

  if (eveEyesConfig) {
    router.use("/eve-eyes", createEveEyesProxy(eveEyesConfig));
  }

  return router;
}

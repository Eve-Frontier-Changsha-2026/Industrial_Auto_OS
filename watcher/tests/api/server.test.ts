import { describe, it, expect, beforeAll, afterAll } from "vitest";
import express from "express";
import { createApiRouter } from "../../src/api/server.js";
import type { Database } from "better-sqlite3";
import { createDb } from "../../src/db/sqlite.js";

describe("Watcher REST API", () => {
  let db: Database;
  let app: express.Express;

  beforeAll(() => {
    db = createDb(":memory:");
    db.prepare(
      "INSERT INTO tx_log (rule_name, tx_digest, status, gas_used, created_at) VALUES (?, ?, ?, ?, ?)"
    ).run("production_completer", "0xABC123", "success", 1500000, Date.now());
    db.prepare(
      "INSERT INTO tx_log (rule_name, tx_digest, status, error, gas_used, created_at) VALUES (?, ?, ?, ?, ?, ?)"
    ).run("order_acceptor", "0xDEF456", "fail", "InsufficientGas", 0, Date.now());

    const mockRegistry = {
      listAll: () => [
        { name: "production_completer", description: "Complete finished jobs", enabled: true },
        { name: "order_acceptor", description: "Accept work orders", enabled: false },
      ],
    };

    app = express();
    app.use("/", createApiRouter(db, mockRegistry as any));
  });

  afterAll(() => db.close());

  it("GET /health returns uptime and version", async () => {
    const res = await requestApp(app, "/health");
    expect(res.status).toBe(200);
    const body = JSON.parse(res.body);
    expect(body).toHaveProperty("uptime_ms");
    expect(body).toHaveProperty("last_poll");
    expect(body.status).toBe("ok");
  });

  it("GET /status returns rule handler states", async () => {
    const res = await requestApp(app, "/status");
    expect(res.status).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.rules).toHaveLength(2);
    expect(body.rules[0].name).toBe("production_completer");
    expect(body.rules[0].enabled).toBe(true);
  });

  it("GET /tx-log returns recent transactions", async () => {
    const res = await requestApp(app, "/tx-log");
    expect(res.status).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.transactions).toHaveLength(2);
    expect(body.transactions[0].tx_digest).toBe("0xDEF456"); // newest first
  });

  it("GET /tx-log?limit=1 respects limit", async () => {
    const res = await requestApp(app, "/tx-log?limit=1");
    const body = JSON.parse(res.body);
    expect(body.transactions).toHaveLength(1);
  });

  it("GET /tx-log?status=fail filters by status", async () => {
    const res = await requestApp(app, "/tx-log?status=fail");
    const body = JSON.parse(res.body);
    expect(body.transactions).toHaveLength(1);
    expect(body.transactions[0].status).toBe("fail");
  });
});

async function requestApp(app: express.Express, path: string): Promise<{ status: number; body: string }> {
  const http = await import("node:http");
  return new Promise((resolve) => {
    const server = http.createServer(app);
    server.listen(0, () => {
      const port = (server.address() as any).port;
      http.get(`http://localhost:${port}${path}`, (res: any) => {
        let body = "";
        res.on("data", (chunk: string) => (body += chunk));
        res.on("end", () => {
          server.close();
          resolve({ status: res.statusCode, body });
        });
      });
    });
  });
}

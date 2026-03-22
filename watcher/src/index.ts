import express from "express";
import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { loadConfig } from "./config.js";
import { createDb } from "./db/sqlite.js";
import { SingleKeypairProvider } from "./signer/single.js";
import { GasPool } from "./executor/gas-pool.js";
import { TxExecutor } from "./executor/tx-executor.js";
import { EventPoller } from "./poller/event-poller.js";
import { InventoryMonitor } from "./poller/inventory-monitor.js";
import { DeadlineScheduler } from "./poller/deadline-scheduler.js";
import { FleetListener } from "./poller/fleet-listener.js";
import { RuleRegistry } from "./rules/registry.js";
import { WatcherEngine } from "./engine.js";
import { createApiRouter, updateLastPoll } from "./api/server.js";

// Rule handlers
import { ProductionCompleter } from "./rules/production-completer.js";
import { OutputWithdrawer } from "./rules/output-withdrawer.js";
import { TriggerEvaluator } from "./rules/trigger-evaluator.js";
import { AutoRestock } from "./rules/auto-restock.js";
import { OrderAcceptor } from "./rules/order-acceptor.js";
import { OrderCompleter } from "./rules/order-completer.js";
import { AutoComplete } from "./rules/auto-complete.js";
import { ExpiredCleaner } from "./rules/expired-cleaner.js";
import { DeliveryHandler } from "./rules/delivery-handler.js";
import { LeaseForfeiter } from "./rules/lease-forfeiter.js";
import { FleetDamageHandler } from "./rules/fleet-damage.js";

async function main() {
  const configPath = process.argv[2] ?? "config.yaml";
  console.log(`Loading config from ${configPath}`);
  const config = loadConfig(configPath);

  // ─── Infrastructure ──────────────────────────
  const client = new SuiClient({ url: getFullnodeUrl(config.network) });
  const db = createDb("watcher.db");
  const signer = SingleKeypairProvider.fromKeystoreFile(config.signer.keypath);
  const signers = await signer.listSigners();
  console.log(`Signer: ${signers[0].address}`);

  const gasPool = new GasPool(client, signers[0].address, {
    poolSize: config.gas.pool_size,
    minCoinBalance: config.gas.min_coin_balance,
    minBalanceWarn: config.gas.min_balance_warn,
  });
  await gasPool.initialize();
  console.log(`Gas pool: ${gasPool.size()} coins`);

  const txExecutor = new TxExecutor(client, gasPool, signer, db);

  // ─── Pollers ─────────────────────────────────
  const packageIds = Object.values(config.package_ids);
  const eventPoller = new EventPoller(client, db, packageIds);
  const inventoryMonitor = new InventoryMonitor(
    client, config.watch.production_line_ids, config.watch.item_type_ids,
  );
  const deadlineScheduler = new DeadlineScheduler(db);

  // ─── Rules ───────────────────────────────────
  const registry = new RuleRegistry();
  const { rules, package_ids: pkgs, watch } = config;
  const boardId = watch.work_order_board_id;

  const ruleMap: Record<string, () => import("./rules/interface.js").RuleHandler> = {
    production_completer: () => new ProductionCompleter(pkgs.industrial_core),
    output_withdrawer: () => new OutputWithdrawer(pkgs.industrial_core),
    trigger_evaluator: () => new TriggerEvaluator(pkgs.industrial_core, []),
    auto_restock: () => new AutoRestock(pkgs.industrial_core),
    order_acceptor: () => new OrderAcceptor(pkgs.work_order),
    order_completer: () => new OrderCompleter(pkgs.work_order, boardId),
    auto_complete: () => new AutoComplete(pkgs.work_order, boardId),
    expired_cleaner: () => new ExpiredCleaner(pkgs.work_order, boardId),
    delivery_handler: () => new DeliveryHandler(pkgs.work_order, client),
    lease_forfeiter: () => new LeaseForfeiter(pkgs.marketplace),
    fleet_damage: () => new FleetDamageHandler(pkgs.work_order, boardId),
  };

  for (const [name, factory] of Object.entries(ruleMap)) {
    if (rules[name]?.enabled !== false) {
      const handler = factory();
      handler.enabled = rules[name]?.enabled ?? true;
      registry.register(handler);
    }
  }

  console.log(`Registered ${registry.listAll().length} rules`);

  // ─── Engine ──────────────────────────────────
  const engine = new WatcherEngine(config, db, registry);
  engine.setTxExecutor(txExecutor);

  // ─── REST API ────────────────────────────────
  const apiApp = express();
  apiApp.use((_req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    next();
  });
  apiApp.use("/", createApiRouter(db, registry));
  const apiPort = config.api?.port ?? 3001;
  apiApp.listen(apiPort, () => {
    console.log(`API server on http://localhost:${apiPort}`);
  });

  // ─── Fleet Listener ──────────────────────────
  const fleetConfig = rules.fleet_damage as any;
  const fleetListener = new FleetListener({
    mock: fleetConfig?.mock ?? false,
    intervalMs: fleetConfig?.interval_ms ?? 30000,
    recipeIds: fleetConfig?.recipe_ids ?? [],
    onReport: (report) => {
      engine.dispatch({ type: "fleet", fleetData: report }).catch(console.error);
    },
  });
  fleetListener.start();

  // ─── Main Loop ───────────────────────────────
  let running = true;
  process.on("SIGINT", () => {
    console.log("\nShutting down...");
    running = false;
    fleetListener.stop();
    db.close();
    process.exit(0);
  });

  console.log(`Starting watcher (poll every ${config.watch.poll_interval_ms}ms)`);

  while (running) {
    try {
      updateLastPoll();
      // 1. Poll events
      const events = await eventPoller.poll();
      deadlineScheduler.processEvents(events);
      for (const event of events) {
        await engine.dispatch({ type: "event", eventData: event });
      }

      // 2. Poll inventory
      const snapshots = await inventoryMonitor.poll();
      for (const snapshot of snapshots) {
        await engine.dispatch({ type: "inventory", inventoryData: snapshot });
      }

      // 3. Check deadlines
      const expired = deadlineScheduler.getExpired(Date.now());
      for (const deadline of expired) {
        await engine.dispatch({ type: "deadline", deadlineData: deadline });
        deadlineScheduler.markProcessed(deadline.id);
      }

      // 4. Gas pool health
      if (gasPool.isLowBalance()) {
        console.warn("⚠ Gas pool balance low!");
      }
    } catch (err) {
      console.error("Poll loop error:", err);
    }

    await new Promise((r) => setTimeout(r, config.watch.poll_interval_ms));
  }
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});

import { readFileSync } from "node:fs";
import { parse as parseYaml } from "yaml";
import type { WatcherConfig } from "./types.js";

export function parseConfig(yamlStr: string): WatcherConfig {
  return parseYaml(yamlStr) as WatcherConfig;
}

export function loadConfig(filePath: string): WatcherConfig {
  const raw = readFileSync(filePath, "utf-8");
  const config = parseConfig(raw);
  validateConfig(config);
  return config;
}

export function validateConfig(config: WatcherConfig): void {
  // Network
  if (!["devnet", "testnet", "mainnet"].includes(config.network)) {
    throw new Error(`Invalid network: ${config.network}`);
  }

  // Package IDs
  const { package_ids } = config;
  if (
    !package_ids?.industrial_core ||
    !package_ids?.work_order ||
    !package_ids?.marketplace
  ) {
    throw new Error(
      "Missing required package_ids (industrial_core, work_order, marketplace)",
    );
  }

  // Watch
  if (!config.watch?.production_line_ids?.length) {
    throw new Error("watch.production_line_ids must have at least one entry");
  }
  if (!config.watch?.work_order_board_id) {
    throw new Error("watch.work_order_board_id is required");
  }

  // Gas
  if (config.gas?.pool_size < 1 || config.gas?.pool_size > 100) {
    throw new Error("gas.pool_size must be between 1 and 100");
  }

  // Mutual exclusivity: trigger_evaluator vs auto_restock
  const triggerLines = new Set(
    (config.rules?.trigger_evaluator as any)?.production_line_ids ?? [],
  );
  const restockLines = new Set(
    (config.rules?.auto_restock as any)?.production_line_ids ?? [],
  );
  for (const lineId of triggerLines) {
    if (restockLines.has(lineId)) {
      throw new Error(
        `Production line ${lineId} in both trigger_evaluator and auto_restock — mutually exclusive`,
      );
    }
  }
}

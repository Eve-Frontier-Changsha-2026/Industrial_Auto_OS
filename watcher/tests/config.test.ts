import { describe, it, expect } from "vitest";
import { parseConfig, validateConfig } from "../src/config.js";

const VALID_YAML = `
network: testnet
package_ids:
  industrial_core: "0xCORE"
  work_order: "0xWO"
  marketplace: "0xMKT"
signer:
  type: single
  keypath: ~/.sui/sui.keystore
watch:
  poll_interval_ms: 5000
  production_line_ids: ["0xLINE1"]
  work_order_board_id: "0xBOARD"
  marketplace_id: "0xMARKET"
  item_type_ids: [1, 2, 3]
gas:
  pool_size: 20
  min_balance_warn: 100000000
  min_coin_balance: 5000000
  auto_replenish: true
rules:
  trigger_evaluator:
    enabled: true
    production_line_ids: ["0xLINE1"]
    trigger_rule_ids: ["0xTRIGGER_RULE1"]
  auto_restock:
    enabled: true
    threshold: 10
    production_line_ids: ["0xLINE2"]
    recipe_id: "0xRECIPE1"
    blueprint_id: "0xBLUEPRINT1"
  output_withdrawer:
    enabled: true
  order_acceptor:
    enabled: true
    max_escrow: 5000000000
    recipe_ids: []
  order_completer:
    enabled: true
  auto_complete:
    enabled: true
  expired_cleaner:
    enabled: true
  lease_forfeiter:
    enabled: false
  fleet_damage:
    enabled: true
    mock: true
    interval_ms: 30000
  production_completer:
    enabled: true
  delivery_handler:
    enabled: true
    auto_deliver: true
`;

describe("Config", () => {
  it("parses valid YAML", () => {
    const config = parseConfig(VALID_YAML);
    expect(config.network).toBe("testnet");
    expect(config.package_ids.industrial_core).toBe("0xCORE");
    expect(config.gas.pool_size).toBe(20);
  });

  it("validates config succeeds for valid input", () => {
    const config = parseConfig(VALID_YAML);
    expect(() => validateConfig(config)).not.toThrow();
  });

  it("rejects overlapping production_line_ids between trigger_evaluator and auto_restock", () => {
    const yaml = VALID_YAML.replace(
      'production_line_ids: ["0xLINE2"]',
      'production_line_ids: ["0xLINE1"]',
    );
    const config = parseConfig(yaml);
    expect(() => validateConfig(config)).toThrow(/mutually exclusive/);
  });

  it("rejects missing package_ids", () => {
    const yaml = VALID_YAML.replace("industrial_core", "");
    const config = parseConfig(yaml);
    expect(() => validateConfig(config)).toThrow();
  });

  it("rejects invalid network", () => {
    const yaml = VALID_YAML.replace("testnet", "foonet");
    const config = parseConfig(yaml);
    expect(() => validateConfig(config)).toThrow(/network/);
  });
});

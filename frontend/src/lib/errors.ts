const ERROR_MAP: Record<number, string> = {
  // production_line
  0: "Not owner",
  1: "Not authorized operator",
  2: "Insufficient materials",
  3: "Production line busy",
  4: "Production not complete",
  11: "Recipe/blueprint mismatch",
  12: "Insufficient fuel",
  14: "Zero material after efficiency",
  17: "Max operators reached",
  18: "Invalid item type",
  20: "Insufficient output",
  // blueprint
  5: "No uses left on blueprint copy",
  6: "Max copies reached",
  13: "Efficiency out of range",
  // trigger_engine
  7: "Trigger disabled",
  8: "Trigger condition not met",
  9: "Trigger on cooldown",
  19: "Trigger/line mismatch",
  // work_order
  100: "Insufficient escrow",
  101: "Deadline too far",
  102: "Order already accepted",
  103: "Not issuer",
  104: "Not acceptor",
  105: "Wrong status for operation",
  106: "Delivery type mismatch",
  107: "Delivery quantity exceeds required",
  108: "Not expired",
  109: "Not delivered",
  110: "Auto-complete too early (72h not elapsed)",
  // marketplace
  200: "Listing price too low",
  201: "Not seller",
  202: "Insufficient payment",
  203: "Fee too high",
  204: "Listing inactive",
  // lease
  300: "Not lessee",
  301: "Not lessor",
  302: "Lease not expired",
  303: "Lease inactive",
};

export function humanError(code: number): string {
  return ERROR_MAP[code] ?? `Unknown error (code: ${code})`;
}

import { vi } from "vitest";
import type { SuiClient } from "@mysten/sui/client";

export function createMockSuiClient(
  overrides: Partial<SuiClient> = {},
): SuiClient {
  return {
    getCoins: vi.fn(),
    getObject: vi.fn(),
    getDynamicFieldObject: vi.fn(),
    queryEvents: vi.fn(),
    signAndExecuteTransaction: vi.fn(),
    waitForTransaction: vi.fn(),
    ...overrides,
  } as unknown as SuiClient;
}

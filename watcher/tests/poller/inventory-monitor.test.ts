import { describe, it, expect, vi } from "vitest";
import { InventoryMonitor } from "../../src/poller/inventory-monitor.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";

describe("InventoryMonitor", () => {
  it("polls production line and returns inventory snapshot", async () => {
    const client = createMockSuiClient({
      getObject: vi.fn().mockResolvedValue({
        data: {
          content: {
            fields: {
              status: 0,
              current_job_end: "0",
              fuel_reserve: "500",
            },
          },
        },
      }),
      getDynamicFieldObject: vi.fn().mockResolvedValue({
        data: {
          content: { fields: { value: "3" } },
        },
      }),
    });

    const monitor = new InventoryMonitor(client, ["0xLINE1"], [1, 2]);
    const snapshots = await monitor.poll();

    expect(snapshots).toHaveLength(1);
    expect(snapshots[0].productionLineId).toBe("0xLINE1");
    expect(snapshots[0].items.get(1)).toBe(3);
  });

  it("reads production line status for running jobs", async () => {
    const client = createMockSuiClient({
      getObject: vi.fn().mockResolvedValue({
        data: {
          content: {
            fields: {
              status: 1,
              current_job_end: "1711000000000",
              fuel_reserve: "100",
            },
          },
        },
      }),
      getDynamicFieldObject: vi.fn().mockResolvedValue({
        data: { content: { fields: { value: "50" } } },
      }),
    });

    const monitor = new InventoryMonitor(client, ["0xLINE1"], [1]);
    const snapshots = await monitor.poll();

    expect(snapshots[0].status).toBe(1);
    expect(snapshots[0].currentJobEnd).toBe(1711000000000);
  });
});

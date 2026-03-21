import type { SuiClient } from "@mysten/sui/client";
import type { InventorySnapshot } from "../types.js";

export class InventoryMonitor {
  constructor(
    private client: SuiClient,
    private productionLineIds: string[],
    private itemTypeIds: number[],
  ) {}

  async poll(): Promise<InventorySnapshot[]> {
    const snapshots: InventorySnapshot[] = [];
    for (const lineId of this.productionLineIds) {
      const snapshot = await this.pollLine(lineId);
      if (snapshot) snapshots.push(snapshot);
    }
    return snapshots;
  }

  private async pollLine(
    lineId: string,
  ): Promise<InventorySnapshot | null> {
    const lineObj = await this.client.getObject({
      id: lineId,
      options: { showContent: true },
    });

    const fields = (lineObj.data?.content as any)?.fields;
    if (!fields) return null;

    const items = new Map<number, number>();

    for (const itemTypeId of this.itemTypeIds) {
      try {
        const dynField = await this.client.getDynamicFieldObject({
          parentId: lineId,
          name: { type: "u32", value: itemTypeId },
        });
        const quantity = Number(
          (dynField.data?.content as any)?.fields?.value ?? 0,
        );
        items.set(itemTypeId, quantity);
      } catch {
        items.set(itemTypeId, 0);
      }
    }

    return {
      productionLineId: lineId,
      items,
      status: Number(fields.status),
      currentJobEnd: Number(fields.current_job_end ?? 0),
      fuelReserve: Number(fields.fuel_reserve ?? 0),
    };
  }
}

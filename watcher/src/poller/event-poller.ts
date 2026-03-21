import type { SuiClient, SuiEvent, EventId } from "@mysten/sui/client";
import type Database from "better-sqlite3";
import { getCursor, setCursor } from "../db/sqlite.js";

export class EventPoller {
  private cursors = new Map<string, EventId>();
  private initialized = false;

  constructor(
    private client: SuiClient,
    private db: Database.Database,
    private packageIds: string[],
  ) {}

  private loadCursors(): void {
    if (this.initialized) return;
    for (const pkgId of this.packageIds) {
      const raw = getCursor(this.db, `events:${pkgId}`);
      if (raw) {
        this.cursors.set(pkgId, JSON.parse(raw));
      }
    }
    this.initialized = true;
  }

  async poll(): Promise<SuiEvent[]> {
    this.loadCursors();
    const allEvents: SuiEvent[] = [];

    for (const pkgId of this.packageIds) {
      const cursor = this.cursors.get(pkgId);
      const result = await this.client.queryEvents({
        query: { MoveEventModule: { package: pkgId, module: "*" } },
        cursor: cursor ?? undefined,
        order: "ascending",
      });

      allEvents.push(...result.data);

      if (result.data.length > 0 && result.nextCursor) {
        this.cursors.set(pkgId, result.nextCursor);
        setCursor(
          this.db,
          `events:${pkgId}`,
          JSON.stringify(result.nextCursor),
        );
      }
    }

    return allEvents;
  }
}

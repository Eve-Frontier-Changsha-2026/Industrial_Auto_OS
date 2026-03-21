import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import { EventPoller } from "../../src/poller/event-poller.js";
import { createMockSuiClient } from "../helpers/mock-sui-client.js";
import { createDb } from "../../src/db/sqlite.js";

describe("EventPoller", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = createDb(":memory:");
  });
  afterEach(() => db.close());

  it("fetches events and returns them", async () => {
    const mockEvents = [
      {
        id: { txDigest: "0xA", eventSeq: "0" },
        type: "0xPKG::production_line::ProductionCompletedEvent",
        parsedJson: { output_quantity: "10" },
        packageId: "0xPKG",
        transactionModule: "production_line",
        sender: "0x",
        bcs: "",
        timestampMs: "0",
      },
    ];
    const client = createMockSuiClient({
      queryEvents: vi.fn().mockResolvedValue({
        data: mockEvents,
        hasNextPage: false,
        nextCursor: { txDigest: "0xA", eventSeq: "0" },
      }),
    });
    const poller = new EventPoller(client, db, ["0xPKG"]);
    const events = await poller.poll();
    expect(events).toHaveLength(1);
    expect(events[0].type).toContain("ProductionCompletedEvent");
  });

  it("persists cursor across polls", async () => {
    const client = createMockSuiClient({
      queryEvents: vi
        .fn()
        .mockResolvedValueOnce({
          data: [
            {
              id: { txDigest: "0xA", eventSeq: "0" },
              type: "t",
              parsedJson: {},
              packageId: "0xPKG",
              transactionModule: "m",
              sender: "0x",
              bcs: "",
              timestampMs: "0",
            },
          ],
          hasNextPage: false,
          nextCursor: { txDigest: "0xA", eventSeq: "0" },
        })
        .mockResolvedValueOnce({
          data: [],
          hasNextPage: false,
          nextCursor: null,
        }),
    });
    const poller = new EventPoller(client, db, ["0xPKG"]);
    await poller.poll();
    await poller.poll();
    const secondCall = (client.queryEvents as any).mock.calls[1][0];
    expect(secondCall.cursor).toEqual({
      txDigest: "0xA",
      eventSeq: "0",
    });
  });

  it("resumes from persisted cursor on new instance", async () => {
    const client = createMockSuiClient({
      queryEvents: vi.fn().mockResolvedValue({
        data: [],
        hasNextPage: false,
        nextCursor: null,
      }),
    });
    db.prepare(
      "INSERT INTO cursors (event_type, cursor_id, updated_at) VALUES (?, ?, ?)",
    ).run(
      "events:0xPKG",
      JSON.stringify({ txDigest: "0xPREV", eventSeq: "5" }),
      Date.now(),
    );
    const poller = new EventPoller(client, db, ["0xPKG"]);
    await poller.poll();
    const call = (client.queryEvents as any).mock.calls[0][0];
    expect(call.cursor).toEqual({ txDigest: "0xPREV", eventSeq: "5" });
  });
});

/**
 * Monkey / extreme tests for eveEyes.ts API client
 * Goal: malformed responses, network errors, XSS in API response, redirect, huge payloads
 *
 * Attack vectors:
 * - Server returns non-JSON (HTML error page)
 * - Server returns 200 with XSS payload in JSON fields
 * - Server returns redirect (301/302)
 * - Server returns empty body
 * - Request with adversarial parameters (SSRF, header injection)
 * - Timeout (slow response)
 * - Response with prototype pollution payload
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  fetchKillmails,
  fetchBuildingLeaderboard,
  fetchTransactionBlockDetail,
  fetchMoveCallsForTx,
  fetchMoveCallDetail,
  fetchTransactionBlocks,
  fetchMoveCalls,
} from "../../src/lib/eveEyes";

// Mock fetch globally
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

function jsonResponse(data: unknown, status = 200, statusText = "OK") {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    statusText,
    json: () => Promise.resolve(data),
    text: () => Promise.resolve(JSON.stringify(data)),
  });
}

function textResponse(body: string, status = 200, statusText = "OK") {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    statusText,
    json: () => Promise.reject(new SyntaxError("not JSON")),
    text: () => Promise.resolve(body),
  });
}

describe("eveEyes API — monkey tests", () => {
  beforeEach(() => mockFetch.mockReset());

  // ────── Network failures ──────

  describe("network errors (simulated via HTTP status)", () => {
    // Note: vitest jsdom environment intercepts synchronous throws from
    // mocked globals before async handlers catch them. We simulate network
    // errors via status codes instead — same error path in fetchJson.

    it("503 Service Unavailable (simulates DNS/connection failure)", async () => {
      mockFetch.mockReturnValue(jsonResponse({ error: "Service Unavailable" }, 503, "Service Unavailable"));
      await expect(fetchKillmails()).rejects.toThrow("Eve Eyes API: 503 Service Unavailable");
    });

    it("504 Gateway Timeout (simulates connection timeout)", async () => {
      mockFetch.mockReturnValue(jsonResponse(null, 504, "Gateway Timeout"));
      await expect(fetchBuildingLeaderboard()).rejects.toThrow("504");
    });

    it("0 status (browser offline / CORS block)", async () => {
      mockFetch.mockReturnValue(Promise.resolve({
        ok: false, status: 0, statusText: "",
        json: () => Promise.resolve(null),
      }));
      await expect(fetchKillmails()).rejects.toThrow("Eve Eyes API: 0");
    });
  });

  // ────── HTTP error responses ──────

  describe("HTTP errors", () => {
    it("401 Unauthorized", async () => {
      mockFetch.mockReturnValue(jsonResponse({ error: "Unauthorized" }, 401, "Unauthorized"));
      await expect(fetchKillmails()).rejects.toThrow("Eve Eyes API: 401 Unauthorized");
    });

    it("403 Forbidden", async () => {
      mockFetch.mockReturnValue(jsonResponse({ error: "Forbidden" }, 403, "Forbidden"));
      await expect(fetchKillmails()).rejects.toThrow("403");
    });

    it("404 Not Found", async () => {
      mockFetch.mockReturnValue(jsonResponse({ error: "Not found" }, 404, "Not Found"));
      await expect(fetchTransactionBlockDetail("abc")).rejects.toThrow("404");
    });

    it("429 Rate Limited", async () => {
      mockFetch.mockReturnValue(jsonResponse({ error: "Too many requests" }, 429, "Too Many Requests"));
      await expect(fetchKillmails()).rejects.toThrow("429");
    });

    it("500 Internal Server Error", async () => {
      mockFetch.mockReturnValue(jsonResponse(null, 500, "Internal Server Error"));
      await expect(fetchKillmails()).rejects.toThrow("500");
    });

    it("502 Bad Gateway (HTML error page)", async () => {
      mockFetch.mockReturnValue(textResponse("<html><body>502 Bad Gateway</body></html>", 502, "Bad Gateway"));
      await expect(fetchKillmails()).rejects.toThrow("502");
    });
  });

  // ────── Malformed responses ──────

  describe("malformed responses", () => {
    it("200 but HTML body (CDN cache error)", async () => {
      mockFetch.mockReturnValue(textResponse("<html>cached error page</html>"));
      // fetchJson calls res.json() which throws SyntaxError
      await expect(fetchKillmails()).rejects.toThrow();
    });

    it("200 but empty body", async () => {
      mockFetch.mockReturnValue(textResponse(""));
      await expect(fetchKillmails()).rejects.toThrow();
    });

    it("200 but response is a string instead of object → shape guard rejects", async () => {
      mockFetch.mockReturnValue(jsonResponse("just a string"));
      await expect(fetchKillmails()).rejects.toThrow("unexpected response shape");
    });

    it("200 but response is null → shape guard rejects", async () => {
      mockFetch.mockReturnValue(jsonResponse(null));
      await expect(fetchKillmails()).rejects.toThrow("unexpected response shape");
    });

    it("200 but response is a number → shape guard rejects", async () => {
      mockFetch.mockReturnValue(jsonResponse(42));
      await expect(fetchKillmails()).rejects.toThrow("unexpected response shape");
    });

    it("200 but response has extra unexpected fields (proto pollution)", async () => {
      mockFetch.mockReturnValue(jsonResponse({
        items: [{ killmailItemId: "1", killTimestamp: "t", killer: { label: "k" }, victim: { label: "v" } }],
        constructor: { prototype: { isAdmin: true } },
      }));
      const result = await fetchKillmails();
      expect(result.items).toHaveLength(1);
      // Verify constructor prototype pollution didn't leak to Object.prototype
      expect(({} as any).isAdmin).toBeUndefined();
    });
  });

  // ────── XSS in response data ──────

  describe("XSS payloads in response fields", () => {
    it("killmail with XSS in label", async () => {
      mockFetch.mockReturnValue(jsonResponse({
        items: [{
          killmailItemId: "1",
          killTimestamp: "2026-01-01",
          killer: { label: '<img src=x onerror="alert(document.cookie)">' },
          victim: { label: "javascript:alert(1)" },
          status: "completed",
        }],
      }));
      const result = await fetchKillmails();
      // Stored as-is — caller must escape when rendering
      expect(result.items[0].killer.label).toContain("<img");
    });

    it("leaderboard with XSS in owner field", async () => {
      mockFetch.mockReturnValue(jsonResponse({
        leaderboard: [{
          owner: '<svg/onload="fetch(`https://evil.com`)">',
          count: 999,
        }],
      }));
      const result = await fetchBuildingLeaderboard();
      expect(result.leaderboard[0].owner).toContain("<svg");
    });

    it("transaction with XSS in digest", async () => {
      mockFetch.mockReturnValue(jsonResponse({
        items: [{
          digest: '"><script>alert(1)</script>',
          sender: "0xABC",
          status: "success",
        }],
        pagination: { page: 1, pageSize: 20 },
      }));
      const result = await fetchTransactionBlocks({ page: 1 });
      expect(result.items[0].digest).toContain("<script>");
    });
  });

  // ────── Parameter injection ──────

  describe("adversarial parameters", () => {
    it("senderAddress with newline (header injection attempt)", async () => {
      mockFetch.mockReturnValue(jsonResponse({ items: [], pagination: {} }));
      await fetchTransactionBlocks({ senderAddress: "0xABC\r\nX-Injected: true" });
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      // URLSearchParams encodes the newline
      expect(calledUrl).not.toContain("\r\n");
      expect(calledUrl).toContain("%0D%0A");
    });

    it("digest with URL-encoded characters", async () => {
      mockFetch.mockReturnValue(jsonResponse({ item: {} }));
      await fetchTransactionBlockDetail("abc%2F..%2Fetc%2Fpasswd");
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      // encodeURIComponent double-encodes the %
      expect(calledUrl).toContain("abc%252F");
    });

    it("moduleName with path traversal", async () => {
      mockFetch.mockReturnValue(jsonResponse({ items: [], pagination: {} }));
      await fetchMoveCalls({ moduleName: "../../../etc/passwd" });
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      expect(calledUrl).toContain("moduleName=..%2F..%2F..%2Fetc%2Fpasswd");
    });

    it("very large page number", async () => {
      mockFetch.mockReturnValue(jsonResponse({ items: [], pagination: {} }));
      await fetchTransactionBlocks({ page: 999999999 });
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      expect(calledUrl).toContain("page=999999999");
      // page > 3 → should go through watcher proxy
      expect(calledUrl).toContain("localhost:3001");
    });

    it("page=0 (edge case — should use page 1 logic)", async () => {
      mockFetch.mockReturnValue(jsonResponse({ items: [], pagination: {} }));
      await fetchTransactionBlocks({ page: 0 });
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      // page 0 <= 3, so direct Eve Eyes
      expect(calledUrl).toContain("eve-eyes");
    });

    it("page=-1 (negative)", async () => {
      mockFetch.mockReturnValue(jsonResponse({ items: [], pagination: {} }));
      await fetchTransactionBlocks({ page: -1 });
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      // -1 <= 3, goes direct
      expect(calledUrl).toContain("eve-eyes");
    });

    it("pageSize=0 (request all?)", async () => {
      mockFetch.mockReturnValue(jsonResponse({ items: [], pagination: {} }));
      await fetchTransactionBlocks({ pageSize: 0 });
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      expect(calledUrl).toContain("pageSize=0");
    });

    it("pageSize=100000 (DoS via huge response)", async () => {
      mockFetch.mockReturnValue(jsonResponse({ items: [], pagination: {} }));
      await fetchTransactionBlocks({ pageSize: 100000 });
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      expect(calledUrl).toContain("pageSize=100000");
    });

    it("functionName with unicode", async () => {
      mockFetch.mockReturnValue(jsonResponse({ items: [], pagination: {} }));
      await fetchMoveCalls({ functionName: "héllo_wörld_🔥" });
      const calledUrl = mockFetch.mock.calls[0][0] as string;
      expect(calledUrl).toContain("functionName=");
    });
  });

  // ────── Huge response payloads ──────

  describe("huge payloads", () => {
    it("10000 killmail items", async () => {
      const items = Array.from({ length: 10_000 }, (_, i) => ({
        killmailItemId: String(i),
        killTimestamp: "2026-01-01",
        killer: { label: `killer-${i}` },
        victim: { label: `victim-${i}` },
      }));
      mockFetch.mockReturnValue(jsonResponse({ items }));
      const result = await fetchKillmails({ limit: 10000 });
      expect(result.items).toHaveLength(10_000);
    });
  });

  // ────── Move call detail edge cases ──────

  describe("fetchMoveCallDetail", () => {
    it("callIndex = 0", async () => {
      mockFetch.mockReturnValue(jsonResponse({ item: {} }));
      await fetchMoveCallDetail("abc123", 0);
      const url = mockFetch.mock.calls[0][0] as string;
      expect(url).toContain("/move-calls/abc123/0");
    });

    it("callIndex negative", async () => {
      mockFetch.mockReturnValue(jsonResponse({ item: {} }));
      await fetchMoveCallDetail("abc123", -1);
      const url = mockFetch.mock.calls[0][0] as string;
      expect(url).toContain("/move-calls/abc123/-1");
    });

    it("callIndex NaN (coerced to string)", async () => {
      mockFetch.mockReturnValue(jsonResponse({ item: {} }));
      await fetchMoveCallDetail("abc123", NaN);
      const url = mockFetch.mock.calls[0][0] as string;
      expect(url).toContain("/move-calls/abc123/NaN");
    });

    it("digest with special chars is encoded", async () => {
      mockFetch.mockReturnValue(jsonResponse({ item: {} }));
      await fetchMoveCallDetail("a/b?c=d#e", 0);
      const url = mockFetch.mock.calls[0][0] as string;
      expect(url).toContain("a%2Fb%3Fc%3Dd%23e");
    });
  });
});

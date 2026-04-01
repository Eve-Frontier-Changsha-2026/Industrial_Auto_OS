/**
 * Monkey / extreme tests for useToast
 * Goal: overflow toast ID counter, XSS in message, rapid fire
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useToastState } from "../../src/hooks/useToast";

describe("useToastState — monkey tests", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("rapid fire 1000 toasts doesn't crash", () => {
    const { result } = renderHook(() => useToastState());
    act(() => {
      for (let i = 0; i < 1000; i++) {
        result.current.addToast(`msg-${i}`, "info");
      }
    });
    expect(result.current.toasts.length).toBe(1000);
  });

  it("toasts auto-dismiss after 5s", () => {
    const { result } = renderHook(() => useToastState());
    act(() => result.current.addToast("test", "ok"));
    expect(result.current.toasts.length).toBe(1);
    act(() => vi.advanceTimersByTime(5001));
    expect(result.current.toasts.length).toBe(0);
  });

  it("dismiss non-existent ID is a no-op", () => {
    const { result } = renderHook(() => useToastState());
    act(() => result.current.addToast("test", "ok"));
    act(() => result.current.dismiss(999999));
    expect(result.current.toasts.length).toBe(1);
  });

  it("dismiss negative ID", () => {
    const { result } = renderHook(() => useToastState());
    act(() => result.current.dismiss(-1));
    expect(result.current.toasts.length).toBe(0);
  });

  it("XSS payload in message — stored as-is (React escapes on render)", () => {
    const { result } = renderHook(() => useToastState());
    const xss = '<script>alert("XSS")</script>';
    act(() => result.current.addToast(xss, "error"));
    // Stored verbatim — React JSX {t.message} auto-escapes, so this is safe
    // as long as nobody uses innerHTML to render it
    expect(result.current.toasts[0].message).toBe(xss);
  });

  it("empty string message", () => {
    const { result } = renderHook(() => useToastState());
    act(() => result.current.addToast("", "info"));
    expect(result.current.toasts[0].message).toBe("");
  });

  it("very long message (10KB)", () => {
    const { result } = renderHook(() => useToastState());
    const longMsg = "A".repeat(10_000);
    act(() => result.current.addToast(longMsg, "error"));
    expect(result.current.toasts[0].message.length).toBe(10_000);
  });

  it("unicode/emoji in message", () => {
    const { result } = renderHook(() => useToastState());
    act(() => result.current.addToast("🔥💀 Error: 測試中文 العربية", "error"));
    expect(result.current.toasts[0].message).toContain("🔥");
  });

  it("null bytes in message", () => {
    const { result } = renderHook(() => useToastState());
    act(() => result.current.addToast("before\0after", "info"));
    expect(result.current.toasts[0].message).toContain("\0");
  });

  it("concurrent add and dismiss", () => {
    const { result } = renderHook(() => useToastState());
    act(() => {
      result.current.addToast("a", "ok");
      result.current.addToast("b", "ok");
    });
    const idA = result.current.toasts[0].id;
    act(() => {
      result.current.dismiss(idA);
      result.current.addToast("c", "ok");
    });
    // "a" dismissed, "b" and "c" remain
    expect(result.current.toasts.map((t) => t.message)).toEqual(["b", "c"]);
  });

  it("default variant is info", () => {
    const { result } = renderHook(() => useToastState());
    act(() => result.current.addToast("test"));
    expect(result.current.toasts[0].variant).toBe("info");
  });
});

const MIST_PER_SUI = 1_000_000_000n;

export function truncateAddress(addr: string, chars = 4): string {
  if (addr.length <= chars * 2 + 4) return addr;
  return `${addr.slice(0, chars + 2)}...${addr.slice(-chars)}`;
}

export function formatSui(mist: bigint | number): string {
  const val = typeof mist === "number" ? BigInt(mist) : mist;
  const whole = val / MIST_PER_SUI;
  const frac = val % MIST_PER_SUI;
  const fracStr = frac.toString().padStart(9, "0").slice(0, 3);
  return `${whole}.${fracStr}`;
}

export function formatTimestamp(ms: number): string {
  return new Date(ms).toLocaleString("en-US", {
    year: "numeric", month: "short", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
    hour12: false,
  });
}

export function formatDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

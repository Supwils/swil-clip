/**
 * Format a unix-ms timestamp as a compact, glanceable relative string.
 *
 * Tuned for the clipboard panel: hyper-compact ("now", "3m", "2h", "yd",
 * "3d", "Sep 12") so it fits in a tiny meta slot without truncating.
 * Anchored against a `now` param so callers can keep displays stable across
 * a render batch (avoid items mid-list jumping from "now" → "1m" mid-paint).
 */
export function formatRelativeTime(timestamp: number, now: number = Date.now()): string {
  const diffMs = Math.max(0, now - timestamp);
  const seconds = Math.floor(diffMs / 1000);

  if (seconds < 10) return "now";
  if (seconds < 60) return `${seconds}s`;

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;

  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;

  const days = Math.floor(hours / 24);
  if (days === 1) return "yd";
  if (days < 7) return `${days}d`;

  const date = new Date(timestamp);
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

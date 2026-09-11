// BOREAL_DIALER_RECENTS_v154
import type { RecentCall } from "./apiClient";
import { recentCallPhone, recentCallWhen } from "./apiClient";

export type RecentRow = { key: string; name: string; direction: "Incoming" | "Outgoing"; inbound: boolean; durationLabel: string | null; timeLabel: string; phone: string; initials: string };
export type RecentGroup = { header: string; rows: RecentRow[] };

export function initialsFor(name: string): string {
  const parts = String(name || "").trim().split(/\s+/).filter(Boolean);
  const first = parts[0];
  if (!first) return "?";
  if (parts.length === 1) return first.slice(0, 2).toUpperCase();
  const last = parts[parts.length - 1] ?? first;
  return ((first[0] ?? "") + (last[0] ?? "")).toUpperCase();
}

export function durationLabel(seconds: number | null | undefined): string | null {
  const total = Number(seconds ?? 0);
  if (!Number.isFinite(total) || total <= 0) return null;
  if (total < 60) return `${Math.round(total)}s`;
  const m = Math.floor(total / 60);
  const s = Math.round(total % 60);
  return s === 0 ? `${m}m` : `${m}m ${s}s`;
}

function startOfDay(d: Date): number { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }
const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

export function dayHeader(when: Date, now: Date = new Date()): string {
  const days = Math.round((startOfDay(now) - startOfDay(when)) / 86_400_000);
  if (days <= 0) return "TODAY";
  if (days === 1) return "YESTERDAY";
  return `${MONTHS[when.getMonth()]} ${when.getDate()}`;
}

export function timeLabel(when: Date): string {
  let hours = when.getHours();
  const suffix = hours >= 12 ? "PM" : "AM";
  hours %= 12;
  if (hours === 0) hours = 12;
  return `${hours}:${String(when.getMinutes()).padStart(2, "0")} ${suffix}`;
}

export function toRow(call: RecentCall, index: number): RecentRow | null {
  const raw = recentCallWhen(call);
  const when = raw ? new Date(raw) : null;
  if (!when || Number.isNaN(when.getTime())) return null;
  const phone = recentCallPhone(call);
  const name = String(call.contact_name || "").trim() || phone || "Unknown";
  const inbound = String(call.direction ?? "").toLowerCase() === "inbound";
  return { key: call.id ?? `${raw}-${index}`, name, direction: inbound ? "Incoming" : "Outgoing", inbound, durationLabel: durationLabel(call.duration_seconds), timeLabel: timeLabel(when), phone, initials: initialsFor(name) };
}

export function subtitleFor(row: RecentRow): string { return [row.direction, row.durationLabel, row.timeLabel].filter(Boolean).join(" · "); }

export function groupRecents(calls: RecentCall[], now: Date = new Date()): RecentGroup[] {
  const dated = calls.map((call, index) => {
    const row = toRow(call, index);
    if (!row) return null;
    const when = new Date(recentCallWhen(call));
    return { row, day: startOfDay(when), when: when.getTime() };
  }).filter((entry): entry is { row: RecentRow; day: number; when: number } => entry !== null).sort((a, b) => b.when - a.when);
  const groups: RecentGroup[] = [];
  let currentDay: number | null = null;
  for (const entry of dated) {
    if (entry.day !== currentDay) { currentDay = entry.day; groups.push({ header: dayHeader(new Date(entry.day), now), rows: [] }); }
    groups[groups.length - 1]?.rows.push(entry.row);
  }
  return groups;
}

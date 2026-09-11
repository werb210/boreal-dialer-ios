import { describe, it, expect } from "vitest";
import { groupRecents, dayHeader, durationLabel, timeLabel, initialsFor, subtitleFor, toRow } from "../recents";
import type { RecentCall } from "../apiClient";
const NOW = new Date(2026, 8, 11, 15); const call = (over: Partial<RecentCall> = {}): RecentCall => ({ id:"c1", direction:"inbound", duration_seconds:50, created_at:new Date(2026,8,11,17,31).toISOString(), phone_number:"+15875551234", contact_name:"Liam Spicer", ...over });
describe("BOREAL_DIALER_RECENTS_v154", () => {
 it("formats headers, durations, times, and initials", () => { expect(dayHeader(new Date(2026,8,10), NOW)).toBe("YESTERDAY"); expect(dayHeader(new Date(2026,8,4), NOW)).toBe("SEP 4"); expect(durationLabel(80)).toBe("1m 20s"); expect(durationLabel(0)).toBeNull(); expect(timeLabel(new Date(2026,8,11,17,31))).toBe("5:31 PM"); expect(initialsFor("Liam Spicer")).toBe("LS"); });
 it("creates design rows and fallbacks", () => { const row=toRow(call(),0)!; expect(subtitleFor(row)).toBe("Incoming · 50s · 5:31 PM"); expect(toRow(call({direction:"outbound"}),0)?.direction).toBe("Outgoing"); expect(toRow(call({contact_name:""}),0)?.name).toBe("+15875551234"); expect(toRow(call({created_at:""}),0)).toBeNull(); });
 it("groups newest calls by day", () => { const groups=groupRecents([call({id:"a",created_at:new Date(2026,8,4,19,9).toISOString()}),call({id:"b",created_at:new Date(2026,8,10,17,31).toISOString()}),call({id:"c",created_at:new Date(2026,8,4,19,18).toISOString()})],NOW); expect(groups.map(g=>g.header)).toEqual(["YESTERDAY","SEP 4"]); expect(groups[1]?.rows.map(r=>r.key)).toEqual(["c","a"]); });
});

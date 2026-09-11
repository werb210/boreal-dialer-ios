import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";
import {
  pinnedStaff,
  initialsOf,
  displayNameOf,
  isCallable,
  QUICK_CALL_SLOTS,
  type QuickCallData,
  type QuickCallStaff,
} from "../quickCall";

const srcDir = path.resolve(__dirname, "../..");

function staff(over: Partial<QuickCallStaff> = {}): QuickCallStaff {
  return { user_id: "u1", name: "Caden Werboweski", email: "c@boreal.financial", identity: "u1", online: true, ...over };
}

describe("BOREAL_DIALER_QUICK_CALL_STAFF_v149", () => {
  it("resolves saved picks in slot order", () => {
    const data: QuickCallData = {
      staff: [staff({ user_id: "a", name: "Ann" }), staff({ user_id: "b", name: "Bob" })],
      slots: ["b", "a"],
    };
    expect(pinnedStaff(data).map((s) => s.name)).toEqual(["Bob", "Ann"]);
  });

  it("skips picks whose staff record is gone", () => {
    const data: QuickCallData = { staff: [staff({ user_id: "a" })], slots: ["a", "missing"] };
    expect(pinnedStaff(data).length).toBe(1);
  });

  it("never shows more than the available slots", () => {
    const data: QuickCallData = {
      staff: ["a", "b", "c", "d"].map((id) => staff({ user_id: id })),
      slots: ["a", "b", "c", "d"],
    };
    expect(pinnedStaff(data).length).toBeLessThanOrEqual(QUICK_CALL_SLOTS);
  });

  it("renders nothing with no data", () => {
    expect(pinnedStaff(null)).toEqual([]);
    expect(pinnedStaff({ staff: [], slots: [] })).toEqual([]);
  });

  it("treats a staff member with no twilio identity as not callable", () => {
    expect(isCallable(staff())).toBe(true);
    expect(isCallable(staff({ identity: null }))).toBe(false);
  });

  it("builds initials from a name, falling back to the email", () => {
    expect(initialsOf("Caden Werboweski")).toBe("CW");
    expect(initialsOf("Andrew")).toBe("AN");
    expect(initialsOf(null, "dana@boreal.financial")).toBe("DA");
    expect(initialsOf(null, null)).toBe("?");
  });

  it("never displays a raw email address as the label", () => {
    expect(displayNameOf(staff({ name: null }))).toBe("c");
    expect(displayNameOf(staff({ name: null, email: null }))).toBe("Staff");
  });

  it("calls staff internally rather than dialling a PSTN number", () => {
    const src = fs.readFileSync(path.join(srcDir, "lib/quickCall.ts"), "utf8");
    expect(src).toContain("/api/voice/calls");
    expect(src).toContain("staffIdentity");
    expect(src).not.toContain("setDialPrefill");
  });

  it("loads the same staff endpoint the portal uses", () => {
    const src = fs.readFileSync(path.join(srcDir, "lib/quickCall.ts"), "utf8");
    expect(src).toContain("/api/telephony/quick-call");
  });

  it("the calls tab no longer builds the rail from call history", () => {
    const src = fs.readFileSync(path.join(srcDir, "ui/CallsTab.tsx"), "utf8");
    expect(src).toContain("<QuickCallRail />");
    expect(src).not.toContain('className="bd-qc"');
  });
});

describe("BOREAL_DIALER_QUICK_CALL_EDIT_v154", () => {
  it("sets, moves, and clears slots", async () => {
    const { withSlot } = await import("../quickCall");
    expect(withSlot(["a", "b", "c"], 1, "z")).toEqual(["a", "z", "c"]);
    expect(withSlot(["a", "b", "c"], 2, "a")).toEqual(["", "b", "a"]);
    expect(withSlot(["a", "b", "c"], 0, null)).toEqual(["", "b", "c"]);
  });
});

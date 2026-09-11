import { describe, it, expect, vi, beforeEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import {
  noteCallEnded,
  getEndedCall,
  clearEndedCall,
  subscribeEndedCall,
  isCallSid,
} from "../lastCall";

const SID = "CA" + "a1b2c3d4e5f60718293a4b5c6d7e8f90";
const srcDir = path.resolve(__dirname, "../..");

describe("BOREAL_DIALER_POSTCALL_MOUNT_v161", () => {
  beforeEach(() => clearEndedCall());

  it("recognises a Twilio call sid", () => {
    expect(isCallSid(SID)).toBe(true);
    expect(isCallSid(SID.toUpperCase())).toBe(true);
  });

  it("rejects anything that is not one", () => {
    expect(isCallSid("")).toBe(false);
    expect(isCallSid("CA123")).toBe(false);
    expect(isCallSid("550e8400-e29b-41d4-a716-446655440000")).toBe(false);
    expect(isCallSid(null)).toBe(false);
  });

  it("records a connected call", () => {
    noteCallEnded({ sid: SID, contactName: "+15875551234", connected: true });
    expect(getEndedCall()?.sid).toBe(SID);
    expect(getEndedCall()?.contactName).toBe("+15875551234");
  });

  it("does not ask about a call that never connected", () => {
    noteCallEnded({ sid: SID, contactName: "x", connected: false });
    expect(getEndedCall()).toBeNull();
  });

  it("ignores a call with no usable sid, which cannot be dispositioned", () => {
    noteCallEnded({ sid: "", contactName: "x", connected: true });
    expect(getEndedCall()).toBeNull();
    noteCallEnded({ sid: "not-a-sid", contactName: "x", connected: true });
    expect(getEndedCall()).toBeNull();
  });

  it("falls back to a readable label with no contact name", () => {
    noteCallEnded({ sid: SID, connected: true });
    expect(getEndedCall()?.contactName).toBe("that call");
  });

  it("notifies subscribers on record and on clear", () => {
    const seen = vi.fn();
    const off = subscribeEndedCall(seen);
    noteCallEnded({ sid: SID, contactName: "A", connected: true });
    clearEndedCall();
    expect(seen).toHaveBeenCalledTimes(2);
    expect(seen).toHaveBeenLastCalledWith(null);
    off();
  });

  it("stops notifying after unsubscribe", () => {
    const seen = vi.fn();
    subscribeEndedCall(seen)();
    noteCallEnded({ sid: SID, contactName: "A", connected: true });
    expect(seen).not.toHaveBeenCalled();
  });

  it("the sheet is actually mounted, not just built", () => {
    const screen = fs.readFileSync(path.join(srcDir, "telephony/components/DialerScreen.tsx"), "utf8");
    expect(screen).toContain("<PostCallSheet");
    expect(screen).toContain("clearEndedCall");
  });

  it("hangup captures the call before the handle is dropped", () => {
    const device = fs.readFileSync(path.join(srcDir, "telephony/services/voiceDevice.ts"), "utf8");
    const noteAt = device.indexOf("noteCallEnded(");
    const disconnectAt = device.indexOf("activeCall?.disconnect()");
    expect(noteAt).toBeGreaterThan(-1);
    expect(noteAt).toBeLessThan(disconnectAt);
  });
});

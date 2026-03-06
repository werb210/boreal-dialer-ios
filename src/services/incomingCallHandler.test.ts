import { describe, expect, it } from "vitest";
import { clearStore, getCallStoreState } from "../telephony/state/callStore";
import { handleIncomingCall } from "./incomingCallHandler";

describe("incomingCallHandler", () => {
  it("stores incoming call and sets incoming status", () => {
    clearStore();
    const call = {
      parameters: { From: "+15550001111" }
    } as never;

    handleIncomingCall(call);

    expect(getCallStoreState().incomingCall).toBe(call);
    expect(getCallStoreState().callStatus).toBe("ringing");
  });
});

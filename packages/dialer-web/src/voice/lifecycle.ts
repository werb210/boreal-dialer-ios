import type { Call, Device } from "@twilio/voice-sdk";
import { clearActiveCall, getActiveCall, setActiveCall } from "./callState";
import { startHeartbeat, stopHeartbeat } from "./heartbeat";

export async function syncVoiceState(status: "connected" | "ended") {
  await fetch("/api/voice/state", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ status })
  });
}

export function attachCallLifecycleHandlers(device: Device) {
  device.on("incoming", (call: Call) => {
    if (getActiveCall()) {
      call.reject();
      return;
    }

    setActiveCall(call);

    call.on("accept", async () => {
      startHeartbeat();
      await syncVoiceState("connected");
    });

    const onCallEnd = async () => {
      clearActiveCall();
      stopHeartbeat();
      await syncVoiceState("ended");
    };

    call.on("disconnect", onCallEnd);
    call.on("cancel", onCallEnd);
    call.on("error", onCallEnd);
  });
}

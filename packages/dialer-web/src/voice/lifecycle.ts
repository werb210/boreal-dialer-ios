import type { Call, Device } from "@twilio/voice-sdk";
import { api } from "../network/api";
import { clearActiveCall, getActiveCall, setActiveCall } from "./callState";
import { startHeartbeat, stopHeartbeat } from "./heartbeat";

export async function syncVoiceState(status: "connected" | "ended") {
  await api.post("/api/voice/state", { status });
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

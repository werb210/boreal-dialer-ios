import { Device, type Call } from "@twilio/voice-sdk";
import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";
import { setCallStatus } from "../state/callState";
import { twilioEnv } from "../config/env";
import { getDevice, setDevice, clearDevice } from "./deviceSingleton";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";

void twilioEnv;

let tokenExpiryTimeout: ReturnType<typeof setTimeout> | null = null;
let tokenRefreshPromise: Promise<void> | null = null;

type VoiceTokenPayload = {
  token: string;
};

async function logDialerConnect(call: Call): Promise<void> {
  const to = String(call.parameters?.To ?? "");
  const from = String(call.parameters?.From ?? "");
  const callSid = String(call.parameters?.CallSid ?? "");

  await api.post("/api/dialer/log", {
    direction: "outbound",
    to,
    from,
    callSid
  });
}

export async function initDevice(token: string): Promise<Device> {
  const existingDevice = getDevice();
  if (existingDevice) {
    return existingDevice;
  }

  const nextDevice = new Device(token, {
    closeProtection: true
  });
  setDevice(nextDevice);

  nextDevice.on("tokenWillExpire", async () => {
    await refreshToken();
  });

  nextDevice.on("error", () => {
    setCallStatus("ended");
  });

  nextDevice.on("offline", async () => {
    await refreshToken();
  });

  nextDevice.on("incoming", () => {
    setCallStatus("incoming");
  });

  nextDevice.on("connect", (call: Call) => {
    setCallStatus("connected");
    void logDialerConnect(call);
  });

  nextDevice.on("disconnect", () => {
    setCallStatus("ended");
  });

  await nextDevice.register();

  scheduleExpiryRefresh();

  return nextDevice;
}

function scheduleExpiryRefresh() {
  if (!getDevice()) return;

  if (tokenExpiryTimeout) clearTimeout(tokenExpiryTimeout);

  tokenExpiryTimeout = setTimeout(() => {
    void refreshToken();
  }, 1000 * 60 * 45);
}

export async function refreshToken(): Promise<void> {
  const currentDevice = getDevice();
  if (!currentDevice) return;
  if (tokenRefreshPromise) {
    await tokenRefreshPromise;
    return;
  }

  tokenRefreshPromise = (async () => {
    const response = await api.get(TELEPHONY_TOKEN_ENDPOINT);
    const data = assertApiResponse<VoiceTokenPayload>(response.data);

    const deviceToRefresh = getDevice();
    if (!deviceToRefresh) return;

    await deviceToRefresh.updateToken(data.token);
    scheduleExpiryRefresh();
  })();

  try {
    await tokenRefreshPromise;
  } finally {
    tokenRefreshPromise = null;
  }
}

export function getManagedDevice(): Device | null {
  return getDevice();
}

export function destroyDevice(): void {
  if (tokenExpiryTimeout) {
    clearTimeout(tokenExpiryTimeout);
    tokenExpiryTimeout = null;
  }

  const currentDevice = getDevice();
  if (currentDevice) {
    currentDevice.destroy();
    clearDevice();
  }

  tokenRefreshPromise = null;
  setCallStatus("idle");
}

if (typeof window !== "undefined") {
  window.addEventListener("online", async () => {
    await refreshToken();
  });
}

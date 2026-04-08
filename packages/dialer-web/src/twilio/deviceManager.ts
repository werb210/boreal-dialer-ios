import { Device, type Call } from "@twilio/voice-sdk";
import { api } from "../network/api";
import { setCallStatus } from "../state/callState";
import { twilioEnv } from "../config/env";
import { getDevice, setDevice, clearDevice } from "./deviceSingleton";
import { getTwilioToken } from "../services/twilioTokenService";
import { isTokenExpired } from "../auth/token";
import { registerAuthResetter } from "../auth/useDialerAuth";

void twilioEnv;

let tokenExpiryTimeout: ReturnType<typeof setTimeout> | null = null;
let tokenRefreshPromise: Promise<void> | null = null;

function isExpired(token: string): boolean {
  return isTokenExpired(token);
}

function assertValidDeviceToken(token: string): void {
  if (!token || isExpired(token)) {
    throw new Error("DEVICE_INIT_WITH_INVALID_TOKEN");
  }
}

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
  assertValidDeviceToken(token);

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
    const { token } = await getTwilioToken();
    assertValidDeviceToken(token);

    const deviceToRefresh = getDevice();
    if (!deviceToRefresh) return;

    await deviceToRefresh.updateToken(token);
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
  currentDevice?.destroy?.();
  clearDevice();

  tokenRefreshPromise = null;
  setCallStatus("idle");
}

registerAuthResetter(() => {
  destroyDevice();
});

if (typeof window !== "undefined") {
  window.addEventListener("online", async () => {
    await refreshToken();
  });
}

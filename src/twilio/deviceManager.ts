import { Device } from "@twilio/voice-sdk";
import { setCallStatus } from "../state/callState";

let device: Device | null = null;
let tokenExpiryTimeout: ReturnType<typeof setTimeout> | null = null;
let tokenRefreshPromise: Promise<void> | null = null;

export async function initDevice(token: string): Promise<Device> {
  if (device) {
    device.destroy();
    device = null;
  }

  device = new Device(token, {
    closeProtection: true
  });

  device.on("tokenWillExpire", async () => {
    await refreshToken();
  });

  device.on("error", () => {
    // silent fail — no console
  });

  device.on("offline", async () => {
    await refreshToken();
  });

  device.on("incoming", () => {
    setCallStatus("incoming");
  });

  device.on("connect", () => {
    setCallStatus("connected");
  });

  device.on("disconnect", () => {
    setCallStatus("ended");
  });

  await device.register();

  scheduleExpiryRefresh();

  return device;
}

function scheduleExpiryRefresh() {
  if (!device) return;

  if (tokenExpiryTimeout) clearTimeout(tokenExpiryTimeout);

  tokenExpiryTimeout = setTimeout(() => {
    void refreshToken();
  }, 1000 * 60 * 45);
}

export async function refreshToken(): Promise<void> {
  if (!device) return;
  if (tokenRefreshPromise) {
    await tokenRefreshPromise;
    return;
  }

  tokenRefreshPromise = (async () => {
    const res = await fetch("/api/dialer/token", {
      credentials: "include"
    });

    const data = await res.json();

    if (!device) return;

    await device.updateToken(data.token);
    scheduleExpiryRefresh();
  })();

  try {
    await tokenRefreshPromise;
  } finally {
    tokenRefreshPromise = null;
  }
}

export function getDevice(): Device | null {
  return device;
}

export function destroyDevice(): void {
  if (tokenExpiryTimeout) {
    clearTimeout(tokenExpiryTimeout);
    tokenExpiryTimeout = null;
  }

  if (device) {
    device.destroy();
    device = null;
  }

  tokenRefreshPromise = null;
  setCallStatus("idle");
}

if (typeof window !== "undefined") {
  window.addEventListener("online", async () => {
    await refreshToken();
  });
}

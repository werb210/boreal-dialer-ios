import { Call, Device } from "@twilio/voice-sdk";
import {
  clearIncomingCall,
  getCallStoreState,
  setActiveCall,
  setCallStatus,
  setDevice,
  setIncomingCall,
  setNetworkBanner,
  setUiError
} from "../state/callStore";
import { runTelephonyAuthFlow } from "./telephonyAuthFlow";
import { clearAuth } from "../../auth/useDialerAuth";
import { isTokenExpired } from "../../auth/token";

let device: Device | null = null;
let deviceReady = false;
let initializing: Promise<Device> | null = null;
let session: { isAuthenticated: boolean; token?: string } = { isAuthenticated: false };

function isExpired(token: string): boolean {
  return isTokenExpired(token);
}

function assertDeviceStateTransition(previousState: string | undefined, nextState: string | undefined) {
  if (previousState === "registered" && nextState !== "registered") {
    throw new Error("INVALID_STATE_REGRESSION");
  }
}

async function refreshToken(currentDevice: Device) {
  try {
    const { token } = await runTelephonyAuthFlow();
    if (!token || isExpired(token)) {
      throw new Error("DEVICE_INIT_WITH_INVALID_TOKEN");
    }
    await currentDevice.updateToken(token);
    session = { isAuthenticated: true, token };
    setNetworkBanner(null);
    setUiError(null);
  } catch (error) {
    setUiError("Telephony token refresh failed.");
    clearAuth();
    console.error("[INVARIANT_VIOLATION]", error);
    throw new Error("TOKEN_REFRESH_FAILED");
  }
}

function bindDeviceEvents(currentDevice: Device) {
  currentDevice.on("incoming", (call: Call) => {
    setIncomingCall(call);
    setCallStatus("ringing");
  });

  currentDevice.on("tokenWillExpire", async () => {
    await refreshToken(currentDevice);
  });

  currentDevice.on("offline", async () => {
    const prevState = (currentDevice as Device & { state?: string }).state;
    deviceReady = false;
    setNetworkBanner("Connection lost. Attempting reconnect.");
    await refreshToken(currentDevice);
    const nextState = (currentDevice as Device & { state?: string }).state;
    assertDeviceStateTransition(prevState, nextState);
  });

  currentDevice.on("error", () => {
    const prevState = (currentDevice as Device & { state?: string }).state;
    deviceReady = false;
    setNetworkBanner("Connection lost. Attempting reconnect.");
    const nextState = (currentDevice as Device & { state?: string }).state;
    assertDeviceStateTransition(prevState, nextState);
  });

  currentDevice.on("registered", () => {
    const previousState = (currentDevice as Device & { state?: string }).state;
    deviceReady = true;
    setNetworkBanner(null);
    assertDeviceStateTransition(previousState, "registered");
  });
}

async function initializeDevice() {
  if (device) {
    return device;
  }

  const { token } = await runTelephonyAuthFlow();
  if (!token || isExpired(token)) {
    throw new Error("DEVICE_INIT_WITH_INVALID_TOKEN");
  }

  const nextDevice = new Device(token, {
    codecPreferences: [Call.Codec.Opus, Call.Codec.PCMU]
  });

  bindDeviceEvents(nextDevice);
  setDevice(nextDevice);
  device = nextDevice;

  await nextDevice.register();

  if ((device as Device & { state?: string }).state !== "registered") {
    throw new Error("DEVICE_NOT_READY");
  }

  deviceReady = true;
  session = { isAuthenticated: true, token };
  setUiError(null);

  return device;
}

async function initVoiceDevice() {
  if (!initializing) {
    initializing = initializeDevice().finally(() => {
      initializing = null;
    });
  }

  return initializing;
}

function assertAuthenticatedSession() {
  if (!session.isAuthenticated) {
    throw new Error("NOT_AUTHENTICATED");
  }
}

async function startCall(to: string) {
  assertAuthenticatedSession();

  const currentDevice = await initVoiceDevice();
  if (!device || (device as Device & { state?: string }).state !== "registered") {
    throw new Error("DEVICE_NOT_READY");
  }

  const call = await currentDevice.connect({ params: { to } });
  setActiveCall(call);
  setCallStatus("connecting");
  return call;
}

export async function startDialerSession(to?: string) {
  try {
    await initVoiceDevice();
  } catch (error) {
    setUiError("Telephony initialization failed.");
    throw error;
  }

  if (to) {
    return startCall(to);
  }

  return getDevice();
}

export function getDevice() {
  return device;
}

export function __resetVoiceDeviceForTests() {
  device = null;
  deviceReady = false;
  initializing = null;
  session = { isAuthenticated: false };
  setDevice(null);
  setIncomingCall(null);
  setActiveCall(null);
  setCallStatus("idle");
  setNetworkBanner(null);
  setUiError(null);
}

export function __setSessionForTests(nextSession: { isAuthenticated: boolean; token?: string }) {
  session = nextSession;
}

export function __getSessionForTests() {
  return session;
}

export function answerIncomingCall() {
  const { incomingCall } = getCallStoreState();
  incomingCall?.accept();
  setActiveCall(incomingCall);
  clearIncomingCall();
  setCallStatus("in-call");
}

export function rejectIncomingCall() {
  const { incomingCall } = getCallStoreState();
  incomingCall?.reject();
  clearIncomingCall();
  setCallStatus("ended");
}

export function hangupCall() {
  const { activeCall } = getCallStoreState();
  activeCall?.disconnect();
  setActiveCall(null);
  setCallStatus("ended");
}

export function muteCall() {
  const { activeCall } = getCallStoreState();
  activeCall?.mute(true);
}

export function unmuteCall() {
  const { activeCall } = getCallStoreState();
  activeCall?.mute(false);
}

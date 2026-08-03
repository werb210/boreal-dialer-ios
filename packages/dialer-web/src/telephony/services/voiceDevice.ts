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
import { api } from "../../network/api";
import { API_ENDPOINTS } from "../../constants/endpoints";
import { clearAuth, registerAuthResetter } from "../../auth/useDialerAuth";
import { isTokenExpired } from "../../auth/token";

let device: Device | null = null;
let deviceReady = false;
export function isDeviceReady(): boolean { return deviceReady; } // dialer v2
let initializing: Promise<Device> | null = null;
let refreshPromise: Promise<void> | null = null;
let audioPermissionPrimePromise: Promise<void> | null = null;
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
  if (refreshPromise) {
    return refreshPromise;
  }

  refreshPromise = (async () => {
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
  })();

  try {
    await refreshPromise;
  } finally {
    refreshPromise = null;
  }
}

function tokenValidForDevice(existingDevice: Device, token: string | undefined): boolean {
  return Boolean(existingDevice && token && !isExpired(token));
}

export async function setOutputSafe(currentDevice: Device, deviceId = "default"): Promise<void> {
  try {
    const available = currentDevice.audio?.availableOutputDevices;
    if (!available || available.size === 0) {
      return;
    }

    if (!available.has(deviceId)) {
      const first = available.keys().next().value;
      if (!first) {
        return;
      }
      await currentDevice.audio.speakerDevices.set(first);
      return;
    }

    await currentDevice.audio.speakerDevices.set(deviceId);
  } catch (error) {
    console.warn("[dialer] speaker selection failed, using OS default", error);
  }
}

function primeAudioDeviceEnumeration(): Promise<void> {
  if (audioPermissionPrimePromise) {
    return audioPermissionPrimePromise;
  }

  audioPermissionPrimePromise = (async () => {
    if (typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) {
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.getTracks().forEach((track) => {
        track.stop();
      });
    } catch (error) {
      setUiError("Microphone permission denied. Dialer controls are disabled until access is granted.");
      console.warn("[dialer] microphone permission request failed", error);
    }
  })();

  return audioPermissionPrimePromise;
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

  currentDevice.audio?.on?.("deviceChange", () => {
    void setOutputSafe(currentDevice);
  });
}

async function initializeDevice() {
  if (device) {
    if (!tokenValidForDevice(device, session.token)) {
      throw new Error("DEVICE_INIT_WITH_INVALID_TOKEN");
    }
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

  await primeAudioDeviceEnumeration();
  await nextDevice.register();
  await setOutputSafe(nextDevice);

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

function resetVoiceState(): void {
  device = null;
  deviceReady = false;
  initializing = null;
  refreshPromise = null;
  audioPermissionPrimePromise = null;
  session = { isAuthenticated: false };
  setDevice(null);
  setIncomingCall(null);
  setActiveCall(null);
  setCallStatus("idle");
  setNetworkBanner(null);
  setUiError(null);
}

registerAuthResetter(resetVoiceState);

// BOREAL_DIALER_WEB_JOIN_CONFERENCE_v47
// This never called POST /api/voice/calls at all. It went straight to
// device.connect({ params: { To } }), which lands on the legacy Dial-Number
// branch of /api/webhooks/twilio/voice/twiml - so a call from here had no
// conference behind it and every mid-call control (mute, hold, transfer, add
// participant, recording) had nothing to operate on.
//
// The server's contract, stated at the top of src/routes/voiceCalls.ts: it
// creates the conference, dials the target into it, and returns
// conferenceFriendly for this leg to join with. BF-portal's dialer has always
// done this; this package never did.
//
// To is sent alongside conferenceFriendly because the conference branch reads
// params.To to write the outbound call_logs row.
async function startCall(to: string) {
  assertAuthenticatedSession();

  const currentDevice = await initVoiceDevice();
  if (!device || (device as Device & { state?: string }).state !== "registered") {
    throw new Error("DEVICE_NOT_READY");
  }

  let conferenceFriendly = "";
  try {
    const response = await api.post(API_ENDPOINTS.VOICE_CALLS, { to });
    const body = response?.data?.data ?? response?.data;
    if (body?.ok && typeof body?.conferenceFriendly === "string") {
      conferenceFriendly = body.conferenceFriendly;
    }
  } catch (error) {
    // The call is still worth placing without controls, but this must be
    // visible rather than silent - a silent version of exactly this is what
    // hid the problem for months.
    console.error("[voice] conference setup failed; placing an uncontrolled call", error);
  }

  const params: Record<string, string> = { To: to };
  if (conferenceFriendly) {
    params.conferenceFriendly = conferenceFriendly;
  }

  const call = await currentDevice.connect({ params });
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
  resetVoiceState();
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

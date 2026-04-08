import { useSyncExternalStore } from "react";
import type { Call, Device } from "@twilio/voice-sdk";

export type CallStoreState = {
  device: Device | null;
  incomingCall: Call | null;
  activeCall: Call | null;
  incomingFrom: string | null;
  callStatus: "idle" | "ringing" | "connecting" | "in-call" | "ended";
  callDuration: number;
  networkStatus: "online" | "offline";
  networkBanner: string | null;
  uiError: string | null;
};

type Listener = () => void;

const state: CallStoreState = {
  device: null,
  incomingCall: null,
  activeCall: null,
  incomingFrom: null,
  callStatus: "idle",
  callDuration: 0,
  networkStatus: typeof navigator !== "undefined" && !navigator.onLine ? "offline" : "online",
  networkBanner: null,
  uiError: null
};

const listeners = new Set<Listener>();

function emitChange() {
  listeners.forEach((listener) => {
    listener();
  });
}

let networkListenersBound = false;

export function updateNetworkStatus(networkStatus: CallStoreState["networkStatus"]) {
  state.networkStatus = networkStatus;
  if (networkStatus === "online" && state.networkBanner === "Connection lost. Attempting reconnect.") {
    state.networkBanner = null;
  }
  emitChange();
}

function bindNetworkListeners() {
  if (networkListenersBound || typeof window === "undefined") {
    return;
  }

  networkListenersBound = true;

  window.addEventListener("online", () => {
    updateNetworkStatus("online");
  });

  window.addEventListener("offline", () => {
    updateNetworkStatus("offline");
  });
}

bindNetworkListeners();

export function setDevice(device: Device | null) {
  state.device = device;
  emitChange();
}

export function setIncomingCall(incomingCall: Call | null) {
  state.incomingCall = incomingCall;
  state.incomingFrom = incomingCall ? String(incomingCall.parameters.From ?? "unknown") : null;
  emitChange();
}

export function setActiveCall(activeCall: Call | null) {
  state.activeCall = activeCall;
  emitChange();
}

export function clearIncomingCall() {
  state.incomingCall = null;
  state.incomingFrom = null;
  emitChange();
}

export function clearAllCalls() {
  state.incomingCall = null;
  state.incomingFrom = null;
  state.activeCall = null;
  state.callStatus = "ended";
  state.callDuration = 0;
  emitChange();
}

export function setCallStatus(callStatus: CallStoreState["callStatus"]) {
  state.callStatus = callStatus;
  emitChange();
}

export function setCallDuration(callDuration: number) {
  state.callDuration = callDuration;
  emitChange();
}

export function setNetworkBanner(networkBanner: string | null) {
  state.networkBanner = networkBanner;
  state.networkStatus = networkBanner ? "offline" : "online";
  emitChange();
}

export function setUiError(uiError: string | null) {
  state.uiError = uiError;
  emitChange();
}

export function clearStore() {
  state.device = null;
  state.incomingCall = null;
  state.incomingFrom = null;
  state.activeCall = null;
  state.callStatus = "idle";
  state.callDuration = 0;
  state.networkStatus = "online";
  state.networkBanner = null;
  state.uiError = null;
  emitChange();
}

export function getCallStoreState() {
  return state;
}

function subscribe(listener: Listener) {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
}

function getSnapshot() {
  return state;
}

export function useCallStore() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

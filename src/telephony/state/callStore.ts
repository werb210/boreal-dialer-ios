import { useSyncExternalStore } from "react";
import type { Call, Device } from "@twilio/voice-sdk";

export type CallStoreState = {
  device: Device | null;
  incomingCall: Call | null;
  activeCall: Call | null;
  callStatus: "idle" | "incoming" | "connecting" | "connected" | "ended" | "error";
  callDuration: number;
  networkBanner: string | null;
};

type Listener = () => void;

const state: CallStoreState = {
  device: null,
  incomingCall: null,
  activeCall: null,
  callStatus: "idle",
  callDuration: 0,
  networkBanner: null
};

const listeners = new Set<Listener>();

function emitChange() {
  listeners.forEach((listener) => {
    listener();
  });
}

export function setDevice(device: Device | null) {
  state.device = device;
  emitChange();
}

export function setIncomingCall(incomingCall: Call | null) {
  state.incomingCall = incomingCall;
  emitChange();
}

export function setActiveCall(activeCall: Call | null) {
  state.activeCall = activeCall;
  emitChange();
}

export function clearIncomingCall() {
  state.incomingCall = null;
  emitChange();
}

export function clearAllCalls() {
  state.incomingCall = null;
  state.activeCall = null;
  state.callStatus = "ended";
  state.callDuration = 0;
  emitChange();
}

export function setCallStatus(
  callStatus: CallStoreState["callStatus"]
) {
  state.callStatus = callStatus;
  emitChange();
}

export function setCallDuration(callDuration: number) {
  state.callDuration = callDuration;
  emitChange();
}

export function setNetworkBanner(networkBanner: string | null) {
  state.networkBanner = networkBanner;
  emitChange();
}

export function clearStore() {
  state.device = null;
  state.incomingCall = null;
  state.activeCall = null;
  state.callStatus = "idle";
  state.callDuration = 0;
  state.networkBanner = null;
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

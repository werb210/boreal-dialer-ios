import { useSyncExternalStore } from "react";
import type { Call } from "@twilio/voice-sdk";

type CallStoreState = {
  incomingCall: Call | null;
  activeCall: Call | null;
};

type Listener = () => void;

const state: CallStoreState = {
  incomingCall: null,
  activeCall: null
};

const listeners = new Set<Listener>();

function emitChange() {
  listeners.forEach((listener) => {
    listener();
  });
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

export function clearAll() {
  state.incomingCall = null;
  state.activeCall = null;
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

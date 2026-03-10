export type VoiceCall = {
  disconnect: () => void;
};

let activeCall: VoiceCall | null = null;

export function setActiveCall(call: VoiceCall) {
  if (activeCall && activeCall !== call) {
    activeCall.disconnect();
  }
  activeCall = call;
}

export function clearActiveCall() {
  activeCall = null;
}

export function getActiveCall() {
  return activeCall;
}

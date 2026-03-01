let activeCall: any = null;

export function setActiveCall(call: any) {
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

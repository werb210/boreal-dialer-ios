type CallControlTarget = {
  disconnect: () => void
  mute: (muted: boolean) => void
}

export function hangupCall(call: CallControlTarget) {
  call.disconnect()
}

export function muteCall(call: CallControlTarget) {
  call.mute(true)
}

export function unmuteCall(call: CallControlTarget) {
  call.mute(false)
}

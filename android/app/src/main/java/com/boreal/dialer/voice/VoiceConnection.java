package com.boreal.dialer.voice;

// BOREAL_ANDROID_DIALER_v1 - one Telecom call. Telecom (lock screen, Bluetooth headset, car kit, Wear OS) drives the
// call through these callbacks; each one is passed to VoiceCallManager, which owns the Twilio call.

import android.content.Context;
import android.telecom.CallAudioState;
import android.telecom.Connection;
import android.telecom.DisconnectCause;

public class VoiceConnection extends Connection {

    private final Context context;
    private final String uuid;

    VoiceConnection(Context context, String uuid) {
        this.context = context.getApplicationContext();
        this.uuid = uuid;
        setConnectionProperties(PROPERTY_SELF_MANAGED);
        setConnectionCapabilities(CAPABILITY_MUTE);
        setAudioModeIsVoip(true);
    }

    String uuid() {
        return uuid;
    }

    private VoiceCallManager manager() {
        return VoiceCallManager.get(context);
    }

    /** Telecom wants the ringing UI: our own call notification with a full-screen call screen. */
    @Override
    public void onShowIncomingCallUi() {
        VoiceCallManager.CallSession s = manager().current();
        if (s != null && s.uuid.equals(uuid)) CallNotifications.showIncoming(context, s);
    }

    @Override
    public void onAnswer() {
        manager().answer(uuid);
    }

    @Override
    public void onAnswer(int videoState) {
        manager().answer(uuid);
    }

    @Override
    public void onReject() {
        manager().reject(uuid);
    }

    @Override
    public void onDisconnect() {
        manager().hangup();
    }

    @Override
    public void onAbort() {
        manager().hangup();
    }

    @Override
    public void onCallAudioStateChanged(CallAudioState state) {
        manager().onAudioState(state);
    }

    void destroyWith(int cause) {
        try {
            setDisconnected(new DisconnectCause(cause));
        } catch (RuntimeException ignored) {
            // already disconnected
        }
        destroy();
    }
}

package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - every Firebase message for the app arrives here: Twilio incoming-call messages go to the
// calling engine (they ring through Android Telecom); the server's staff alerts are data-only messages drawn by
// StaffAlertNotifier, so they show even when the app is closed. A rotated token re-registers with Twilio and the server.

import androidx.annotation.NonNull;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;

import com.boreal.dialer.voice.VoiceCallManager;

public class DialerMessagingService extends FirebaseMessagingService {

    @Override
    public void onMessageReceived(@NonNull RemoteMessage message) {
        Map<String, String> data = message.getData();
        if (VoiceCallManager.get(this).handleFcm(data)) return;
        StaffAlertNotifier.show(this, data);
    }

    @Override
    public void onNewToken(@NonNull String token) {
        if (!Session.signedIn(this)) return;
        VoiceSetup.register(this, null);
        PushRegistrar.send(getApplicationContext(), token, true);
    }
}

package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - at launch a saved session registers for calls straight away, so a relaunched or updated app
// rings without signing in again (the iPhone dialler's resumeSavedSession).

import android.app.Application;

import com.boreal.dialer.voice.CallNotifications;

public class DialerApplication extends Application {

    @Override
    public void onCreate() {
        super.onCreate();
        CallNotifications.ensureChannels(this);
        StaffAlertNotifier.ensureChannels(this);
        if (Session.signedIn(this)) {
            VoiceSetup.register(this, null);
            PushRegistrar.upload(this, false);
        }
    }
}

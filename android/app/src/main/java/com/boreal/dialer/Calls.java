package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - places a call from any screen: checks the number and the microphone, asks the server for a
// fresh calling token, starts the call (Android Telecom + Twilio) and opens the call screen.

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;

import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.HashMap;
import java.util.Map;

import com.boreal.dialer.voice.CallActivity;
import com.boreal.dialer.voice.VoiceCallManager;

public final class Calls {

    public static final int MIC_REQUEST = 51;
    @Nullable private static String pendingNumber;
    @Nullable private static String pendingName;

    private Calls() { }

    public static void start(Activity a, @Nullable String raw, @Nullable String name) {
        String number = PhoneNumbers.e164(raw);
        if (number == null) {
            Ui.toast(a, "That phone number isn't valid. Use 10 digits, or + and the country code.");
            return;
        }
        if (ContextCompat.checkSelfPermission(a, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingNumber = number;
            pendingName = name;
            ActivityCompat.requestPermissions(a, new String[] { Manifest.permission.RECORD_AUDIO }, MIC_REQUEST);
            return;
        }
        VoiceCallManager manager = VoiceCallManager.get(a);
        if (manager.current() != null) {
            a.startActivity(new Intent(a, CallActivity.class).setAction(CallActivity.ACTION_SHOW));
            return;
        }
        String label = name != null && !name.trim().isEmpty() ? name.trim() : PhoneNumbers.display(number);
        VoiceSetup.fetchToken(a, (token, err) -> {
            if (token == null) {
                Ui.toast(a, err != null ? err : "The call couldn't be set up. Try again.");
                return;
            }
            Map<String, String> params = new HashMap<>();
            params.put("To", number);
            manager.connect(token, params, label, (ok, error) -> {
                if (!ok) {
                    Ui.toast(a, "busy".equals(error) ? "You're already on a call." : "The call couldn't be set up. Try again.");
                    return;
                }
                a.startActivity(new Intent(a, CallActivity.class).setAction(CallActivity.ACTION_SHOW));
            });
        });
    }

    /** After the microphone question: call the number that was waiting, or explain why not. */
    public static void onMicResult(Activity a, boolean granted) {
        String number = pendingNumber;
        String name = pendingName;
        pendingNumber = null;
        pendingName = null;
        if (number == null) return;
        if (granted) start(a, number, name);
        else Ui.toast(a, a.getString(R.string.mic_needed));
    }
}

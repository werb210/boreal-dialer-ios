package com.boreal.dialer.voice;

// BOREAL_ANDROID_DIALER_v1 - keeps a call alive with the screen off or the app in the background: a foreground service of
// type phoneCall (allowed because the app manages its own calls) plus microphone, showing the ongoing-call
// notification with Hang up. Started when a call is answered or placed, stopped when it ends.

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.app.ServiceCompat;
import androidx.core.content.ContextCompat;

public class VoiceCallService extends Service {

    static void start(Context c) {
        try {
            ContextCompat.startForegroundService(c, new Intent(c, VoiceCallService.class));
        } catch (RuntimeException e) {
            // Background start refused (Android 12+ without a user action): Telecom keeps the call; no notification.
            Log.w("DialerVoice", "call service: " + e.getMessage());
        }
    }

    @SuppressLint("MissingPermission")
    static void update(Context c) {
        VoiceCallManager.CallSession s = VoiceCallManager.get(c).current();
        if (s == null) return;
        try {
            NotificationManagerCompat.from(c).notify(CallNotifications.ID_ONGOING, CallNotifications.ongoing(c, s));
        } catch (RuntimeException ignored) {
            // notifications turned off, or the service was not allowed to start (a call-style notification needs it)
        }
    }

    static void stop(Context c) {
        c.stopService(new Intent(c, VoiceCallService.class));
        NotificationManagerCompat.from(c).cancel(CallNotifications.ID_ONGOING);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        VoiceCallManager.CallSession s = VoiceCallManager.get(this).current();
        if (s == null) {
            stopSelf();
            return START_NOT_STICKY;
        }
        Notification n = CallNotifications.ongoing(this, s);
        int types = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            types = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL;
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO)
                    == android.content.pm.PackageManager.PERMISSION_GRANTED && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                types |= ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE;
            }
        }
        try {
            ServiceCompat.startForeground(this, CallNotifications.ID_ONGOING, n, types);
        } catch (RuntimeException e) {
            try {
                ServiceCompat.startForeground(this, CallNotifications.ID_ONGOING, n,
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ? ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL : 0);
            } catch (RuntimeException again) {
                Log.w("DialerVoice", "foreground refused: " + again.getMessage());
                stopSelf();
            }
        }
        return START_NOT_STICKY;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}

package com.boreal.dialer.voice;

// BOREAL_ANDROID_DIALER_v1 - the call notifications: the ringing call (Android's call style, with Answer and Decline and a
// full-screen call screen over the lock screen) and the ongoing call (with Hang up) that keeps the call's foreground
// service visible. A missed call is not posted here: the server sends the MISSED_CALL staff alert, which names the
// caller from the CRM (the iPhone dialler removes its own duplicate for the same reason).

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.os.Build;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.app.Person;
import androidx.core.content.ContextCompat;

import com.boreal.dialer.R;

public final class CallNotifications {

    static final String CH_INCOMING = "calls_incoming";
    static final String CH_ONGOING = "calls_ongoing";
    static final int ID_INCOMING = 7101;
    static final int ID_ONGOING = 7102;

    private CallNotifications() { }

    public static void ensureChannels(Context c) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm == null) return;
        if (nm.getNotificationChannel(CH_INCOMING) == null) {
            NotificationChannel ch = new NotificationChannel(CH_INCOMING, c.getString(R.string.channel_incoming_calls),
                    NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription(c.getString(R.string.channel_incoming_calls_description));
            ch.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build());
            ch.enableVibration(true);
            ch.setVibrationPattern(new long[] { 0, 800, 600, 800, 600 });
            ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(ch);
        }
        if (nm.getNotificationChannel(CH_ONGOING) == null) {
            NotificationChannel ch = new NotificationChannel(CH_ONGOING, c.getString(R.string.channel_ongoing_calls),
                    NotificationManager.IMPORTANCE_LOW);
            ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(ch);
        }
    }

    private static int immutable() {
        return PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
    }

    static PendingIntent callScreen(Context c, String action, int requestCode) {
        Intent i = new Intent(c, CallActivity.class).setAction(action)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(c, requestCode, i, immutable());
    }

    static PendingIntent broadcast(Context c, String action, int requestCode) {
        Intent i = new Intent(c, CallActionReceiver.class).setAction(action).setPackage(c.getPackageName());
        return PendingIntent.getBroadcast(c, requestCode, i, immutable());
    }

    private static Person caller(VoiceCallManager.CallSession s) {
        return new Person.Builder().setName(s.label()).setImportant(true).build();
    }

    static void showIncoming(Context c, VoiceCallManager.CallSession s) {
        ensureChannels(c);
        PendingIntent screen = callScreen(c, CallActivity.ACTION_SHOW, 1);
        PendingIntent answer = callScreen(c, CallActivity.ACTION_ANSWER, 2);
        PendingIntent decline = broadcast(c, CallActionReceiver.ACTION_DECLINE, 3);
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, CH_INCOMING)
                .setSmallIcon(R.drawable.ic_stat_call)
                .setColor(ContextCompat.getColor(c, R.color.accent))
                .setContentTitle(s.label())
                .setContentText(c.getString(R.string.incoming_call))
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(screen)
                .setFullScreenIntent(screen, true)
                .setStyle(NotificationCompat.CallStyle.forIncomingCall(caller(s), decline, answer));
        notify(c, ID_INCOMING, b.build());
    }

    static Notification ongoing(Context c, VoiceCallManager.CallSession s) {
        ensureChannels(c);
        PendingIntent screen = callScreen(c, CallActivity.ACTION_SHOW, 4);
        PendingIntent hangup = broadcast(c, CallActionReceiver.ACTION_HANGUP, 5);
        String text = "connected".equals(s.phase) ? c.getString(R.string.on_call) : c.getString(R.string.calling);
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, CH_ONGOING)
                .setSmallIcon(R.drawable.ic_stat_call)
                .setColor(ContextCompat.getColor(c, R.color.accent))
                .setContentTitle(s.label())
                .setContentText(text)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(screen)
                .setStyle(NotificationCompat.CallStyle.forOngoingCall(caller(s), hangup));
        if (s.connectedAt > 0) b.setUsesChronometer(true).setWhen(s.connectedAt).setShowWhen(true);
        return b.build();
    }

    static void cancelIncoming(Context c) {
        NotificationManagerCompat.from(c).cancel(ID_INCOMING);
    }

    @SuppressLint("MissingPermission")
    private static void notify(Context c, int id, Notification n) {
        try {
            NotificationManagerCompat.from(c).notify(id, n);
        } catch (RuntimeException e) {
            // Notifications are turned off for the app: Telecom still rings on devices that show self-managed calls.
        }
    }
}

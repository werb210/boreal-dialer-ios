package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - draws the server's staff alerts (staffAlerts.ts, buildStaffFcmData): title, body, categoryId
// (MISSED_CALL, VOICEMAIL, CLIENT_MESSAGE, SMS, HANDOFF, TASK) and optional contactId, phone, voicemailId. A tap opens
// the matching tab; a missed call or voicemail with a number also gets "Call back".

import android.annotation.SuppressLint;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import java.util.Map;

public final class StaffAlertNotifier {

    static final String CH_CALLS = "alerts_calls";
    static final String CH_MESSAGES = "alerts_messages";
    static final String CH_TASKS = "alerts_tasks";

    private StaffAlertNotifier() { }

    static void ensureChannels(Context c) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm == null) return;
        create(nm, CH_CALLS, c.getString(R.string.channel_missed_calls), NotificationManager.IMPORTANCE_HIGH);
        create(nm, CH_MESSAGES, c.getString(R.string.channel_messages), NotificationManager.IMPORTANCE_HIGH);
        create(nm, CH_TASKS, c.getString(R.string.channel_tasks), NotificationManager.IMPORTANCE_DEFAULT);
    }

    private static void create(NotificationManager nm, String id, String name, int importance) {
        if (nm.getNotificationChannel(id) == null) nm.createNotificationChannel(new NotificationChannel(id, name, importance));
    }

    private static String value(Map<String, String> data, String key) {
        String v = data.get(key);
        return v == null ? "" : v.trim();
    }

    private static String channel(String category) {
        switch (AlertRules.channelKind(category)) {
            case "calls": return CH_CALLS;
            case "tasks": return CH_TASKS;
            default: return CH_MESSAGES;
        }
    }

    @SuppressLint("MissingPermission")
    static void show(Context c, Map<String, String> data) {
        if (data == null || !Session.signedIn(c)) return;
        String title = value(data, "title");
        String body = value(data, "body");
        if (title.isEmpty() && body.isEmpty()) return;
        String category = value(data, "categoryId");
        if (!AlertRules.drawsHere(category)) return;
        String phone = value(data, "phone");
        int id = (value(data, "type") + ":" + (value(data, "contactId").isEmpty() ? phone : value(data, "contactId"))).hashCode();
        ensureChannels(c);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;

        Intent tap = new Intent(c, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(MainActivity.EXTRA_TAB, AlertRules.tabFor(category));

        NotificationCompat.Builder b = new NotificationCompat.Builder(c, channel(category))
                .setSmallIcon(R.drawable.ic_stat_call)
                .setColor(ContextCompat.getColor(c, R.color.accent))
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setCategory("TASK".equals(category) ? NotificationCompat.CATEGORY_REMINDER
                        : "calls".equals(AlertRules.channelKind(category)) ? NotificationCompat.CATEGORY_MISSED_CALL
                        : NotificationCompat.CATEGORY_MESSAGE)
                .setPriority("TASK".equals(category) ? NotificationCompat.PRIORITY_DEFAULT : NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(PendingIntent.getActivity(c, id, tap, flags));

        if (AlertRules.offersCallBack(category, phone)) {
            Intent call = new Intent(c, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    .putExtra(MainActivity.EXTRA_CALL, phone);
            b.addAction(0, c.getString(R.string.call_back), PendingIntent.getActivity(c, id + 1, call, flags));
        }
        try {
            NotificationManagerCompat.from(c).notify(id, b.build());
        } catch (RuntimeException ignored) {
            // notifications are turned off for the app
        }
    }
}

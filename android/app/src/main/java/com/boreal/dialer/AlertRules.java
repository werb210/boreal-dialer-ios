package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - which screen a staff alert opens, and whether it gets "Call back". The server sends
// categoryId MISSED_CALL, VOICEMAIL, CLIENT_MESSAGE, SMS, HANDOFF or TASK (staffAlerts.ts, buildStaffFcmData).

import androidx.annotation.Nullable;

public final class AlertRules {

    public static final String TAB_KEYPAD = "keypad";
    public static final String TAB_RECENTS = "recents";
    public static final String TAB_CONTACTS = "contacts";
    public static final String TAB_MESSAGES = "messages";
    public static final String TAB_VOICEMAIL = "voicemail";

    private AlertRules() { }

    public static String tabFor(@Nullable String category) {
        if (category == null) return TAB_RECENTS;
        switch (category) {
            case "VOICEMAIL": return TAB_VOICEMAIL;
            case "SMS":
            case "CLIENT_MESSAGE":
            case "HANDOFF": return TAB_MESSAGES;
            default: return TAB_RECENTS;
        }
    }

    public static String channelKind(@Nullable String category) {
        if ("MISSED_CALL".equals(category) || "VOICEMAIL".equals(category)) return "calls";
        if ("TASK".equals(category)) return "tasks";
        return "messages";
    }

    /**
     * The staff portal app gets the same alerts. The dialler draws calls and messages; tasks are left to the portal
     * (the dialler has no task list), so a phone with both apps never shows an alert twice.
     */
    public static boolean drawsHere(@Nullable String category) {
        return !"TASK".equals(category);
    }

    /** "Call back" only on a missed call or voicemail that came with a proper E.164 number. */
    public static boolean offersCallBack(@Nullable String category, @Nullable String phone) {
        return ("MISSED_CALL".equals(category) || "VOICEMAIL".equals(category))
                && phone != null && phone.trim().matches("^\\+[1-9][0-9]{7,14}$");
    }
}

package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - error messages staff can read (the iPhone dialler's APIError.knownCodes). A server reason is
// shown only when it is a sentence written for people, never a stack trace or SQL error.

import androidx.annotation.Nullable;

import java.util.HashMap;
import java.util.Map;

public final class ApiErrors {

    private static final Map<String, String> KNOWN = new HashMap<>();

    static {
        KNOWN.put("call_not_found", "This call isn't linked to you yet, so the outcome wasn't saved.");
        KNOWN.put("invalid_to", "That phone number isn't valid.");
        KNOWN.put("caller_id_unconfigured", "No outgoing caller ID is set up for your line. Ask an admin.");
        KNOWN.put("call_setup_failed", "The call couldn't be set up. Try again.");
        KNOWN.put("forbidden", "You don't have access to that.");
        KNOWN.put("not_found", "That item no longer exists.");
        KNOWN.put("not_staff", "This number isn't set up as a staff account. Ask an admin to add it.");
        KNOWN.put("invalid_code", "That code isn't right. Check the text message and try again.");
        KNOWN.put("otp_invalid", "That code isn't right. Check the text message and try again.");
        KNOWN.put("otp_expired", "That code has expired. Ask for a new one.");
        KNOWN.put("rate_limited", "Too many tries. Wait a minute and try again.");
    }

    private ApiErrors() { }

    public static boolean isReadable(@Nullable String message) {
        if (message == null) return false;
        String t = message.trim();
        if (t.length() < 8 || t.length() > 200 || !t.contains(" ")) return false;
        String lower = t.toLowerCase();
        String[] technical = { "relation ", "column ", "syntax", "violates", "undefined", "null value", "econn", "error:", "at /", "stack" };
        for (String word : technical) if (lower.contains(word)) return false;
        return true;
    }

    /** The message to show for an HTTP failure. status 0 = no connection. */
    public static String message(int status, @Nullable String code, @Nullable String serverMessage) {
        if (status == 0) return "No connection. Check your signal or Wi-Fi and try again.";
        if (status == 401) return "Your session has expired. Sign in again.";
        if (status == 429) return KNOWN.get("rate_limited");
        if (code != null && KNOWN.containsKey(code)) return KNOWN.get(code);
        if (isReadable(serverMessage)) return serverMessage.trim();
        if (status >= 500) return "The server had a problem (" + status + "). Try again in a moment.";
        if (code != null && !code.isEmpty()) return "The server refused that (" + code + ").";
        return "The server refused that (" + status + ").";
    }
}

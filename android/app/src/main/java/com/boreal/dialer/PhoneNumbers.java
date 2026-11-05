package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - phone numbers the way the iPhone dialler handles them (PhoneFormat.e164): Twilio dials E.164
// only, North American numbers may be typed with or without +1.

import androidx.annotation.Nullable;

public final class PhoneNumbers {

    private PhoneNumbers() { }

    /** "+1 (403) 555-0199", "403-555-0199" or "14035550199" -> "+14035550199"; null when it is not a phone number. */
    @Nullable
    public static String e164(@Nullable String raw) {
        if (raw == null) return null;
        String s = raw.trim();
        if (s.isEmpty() || s.contains("@")) return null;
        if (!s.matches("^[0-9+().\\s-]+$")) return null;
        boolean plus = s.startsWith("+");
        String digits = s.replaceAll("[^0-9]", "");
        if (plus) return digits.matches("^[1-9][0-9]{7,14}$") ? "+" + digits : null;
        if (digits.length() == 10 && digits.charAt(0) >= '2') return "+1" + digits;
        if (digits.length() == 11 && digits.charAt(0) == '1') return "+" + digits;
        return null;
    }

    /** "+14035550199" -> "(403) 555-0199"; other numbers as given. */
    public static String display(@Nullable String raw) {
        if (raw == null) return "";
        String s = raw.replaceFirst("^client:", "").trim();
        String e = e164(s);
        if (e != null && e.startsWith("+1") && e.length() == 12) {
            return "(" + e.substring(2, 5) + ") " + e.substring(5, 8) + "-" + e.substring(8);
        }
        return s;
    }

    /** Keys the keypad accepts. */
    public static boolean isDialKey(char c) {
        return (c >= '0' && c <= '9') || c == '*' || c == '#' || c == '+';
    }
}

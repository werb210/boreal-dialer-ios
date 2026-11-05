package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - reads the role from the sign-in token. Only staff roles take calls (the iPhone dialler's
// AuthService.callingRoles); a client or lender sign-in is refused, because the phone would never ring.

import androidx.annotation.Nullable;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class Jwt {

    private static final String[] CALLING_ROLES = { "admin", "staff", "broker", "ops", "marketing" };

    private Jwt() { }

    @Nullable
    public static String claim(@Nullable String token, String name) {
        if (token == null) return null;
        String[] parts = token.split("\\.");
        if (parts.length < 2) return null;
        try {
            String json = new String(Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
            Matcher m = Pattern.compile("\"" + Pattern.quote(name) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").matcher(json);
            return m.find() ? m.group(1) : null;
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    public static boolean isCallingRole(@Nullable String role) {
        if (role == null) return false;
        String r = role.trim().toLowerCase();
        for (String c : CALLING_ROLES) if (c.equals(r)) return true;
        return false;
    }
}

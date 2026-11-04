package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - the build's settings (app/build.gradle `brand`).

import androidx.annotation.Nullable;

public final class AppConfig {

    private AppConfig() { }

    /** A fixed server (https://host/api), or null when staff find their company's server at sign-in. */
    @Nullable
    public static String fixedApiBase() {
        String v = BuildConfig.API_BASE_URL;
        return v == null || v.trim().isEmpty() ? null : stripSlash(v.trim());
    }

    public static boolean findsServerAtSignIn() { return fixedApiBase() == null; }

    public static String opsUrl() { return stripSlash(BuildConfig.OPS_URL); }

    public static String deepLinkScheme() { return BuildConfig.DEEP_LINK_SCHEME; }

    public static String[] lines() { return BuildConfig.LINES.split(","); }

    public static String lineName(String line) {
        String[] ids = lines();
        String[] names = BuildConfig.LINE_NAMES.split(",");
        for (int i = 0; i < ids.length; i++) if (ids[i].equals(line) && i < names.length) return names[i].trim();
        return line;
    }

    /** "https://host" or "https://host/api" -> "https://host/api". */
    public static String apiBaseFromServer(String serverUrl) {
        String s = stripSlash(serverUrl.trim());
        return s.endsWith("/api") ? s : s + "/api";
    }

    static String stripSlash(String s) {
        String out = s;
        while (out.endsWith("/")) out = out.substring(0, out.length() - 1);
        return out;
    }
}

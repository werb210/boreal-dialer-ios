package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - what the app keeps between launches: the sign-in token, the server it belongs to and the
// line staff call from. Kept in EncryptedSharedPreferences (key in the Android Keystore); a phone whose keystore is
// broken falls back to the app's private storage so it can still be used.

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.security.crypto.EncryptedSharedPreferences;
import androidx.security.crypto.MasterKeys;

public final class Session {

    private static final String FILE = "dialer_session";
    private static final String KEY_TOKEN = "token";
    private static final String KEY_API_BASE = "api_base";
    private static final String KEY_COMPANY = "company";
    private static final String KEY_LINE = "line";
    private static final String KEY_PUSH_TOKEN = "push_token";

    private static SharedPreferences prefs;

    private Session() { }

    private static synchronized SharedPreferences prefs(Context c) {
        if (prefs != null) return prefs;
        Context app = c.getApplicationContext();
        try {
            String master = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC);
            prefs = EncryptedSharedPreferences.create(FILE, master, app,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM);
        } catch (Exception e) {
            Log.w("Dialer", "encrypted storage unavailable: " + e.getClass().getSimpleName());
            prefs = app.getSharedPreferences(FILE + "_plain", Context.MODE_PRIVATE);
        }
        return prefs;
    }

    @Nullable public static String token(Context c) { return prefs(c).getString(KEY_TOKEN, null); }

    public static boolean signedIn(Context c) {
        String t = token(c);
        return t != null && !t.isEmpty() && apiBase(c) != null;
    }

    /** The server every request goes to: https://host/api (a fixed address, or the one chosen at sign-in). */
    @Nullable
    public static String apiBase(Context c) {
        String fixed = AppConfig.fixedApiBase();
        if (fixed != null) return fixed;
        return prefs(c).getString(KEY_API_BASE, null);
    }

    @Nullable public static String company(Context c) { return prefs(c).getString(KEY_COMPANY, null); }

    public static void chooseServer(Context c, String apiBase, @Nullable String company) {
        prefs(c).edit().putString(KEY_API_BASE, apiBase).putString(KEY_COMPANY, company).apply();
    }

    public static void saveToken(Context c, String token) {
        prefs(c).edit().putString(KEY_TOKEN, token).apply();
    }

    public static String line(Context c) {
        String saved = prefs(c).getString(KEY_LINE, null);
        String[] lines = AppConfig.lines();
        if (saved != null) for (String l : lines) if (l.equals(saved)) return saved;
        return lines[0];
    }

    public static void setLine(Context c, String line) { prefs(c).edit().putString(KEY_LINE, line).apply(); }

    @Nullable public static String pushToken(Context c) { return prefs(c).getString(KEY_PUSH_TOKEN, null); }

    public static void setPushToken(Context c, @Nullable String token) {
        if (token == null) prefs(c).edit().remove(KEY_PUSH_TOKEN).apply();
        else prefs(c).edit().putString(KEY_PUSH_TOKEN, token).apply();
    }

    /** Sign-out: the token and the server choice go; the line choice stays. */
    public static void clear(Context c) {
        prefs(c).edit().remove(KEY_TOKEN).remove(KEY_PUSH_TOKEN).remove(KEY_API_BASE).remove(KEY_COMPANY).apply();
    }
}

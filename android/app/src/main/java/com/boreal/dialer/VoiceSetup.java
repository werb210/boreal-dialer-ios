package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - gets this phone ready to take calls: a Twilio access token from the server
// (POST /api/voice/token with app "dialer-android", so the token names the server's Android (FCM) Twilio push
// credential, TWILIO_PUSH_CREDENTIAL_SID_ANDROID), then a Twilio registration with the Firebase token. Runs at
// sign-in, at every launch, every 50 minutes while the app is open, and when Firebase rotates the token.
// A call placed from the app always asks for a fresh token first.

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;

import org.json.JSONException;
import org.json.JSONObject;

import com.boreal.dialer.voice.VoiceCallManager;

public final class VoiceSetup {

    public static final String VOICE_APP = "dialer-android";
    private static final long REFRESH_MS = 50L * 60L * 1000L;
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static Runnable refresher;

    public interface TokenCallback {
        void done(@Nullable String token, @Nullable String error);
    }

    private VoiceSetup() { }

    /** The token sits at the top level or under data (both shapes appear across the servers). */
    @Nullable
    static String tokenFrom(@Nullable JSONObject body) {
        if (body == null) return null;
        String t = body.optString("token", "");
        if (t.isEmpty()) {
            JSONObject data = body.optJSONObject("data");
            if (data != null) t = data.optString("token", "");
        }
        return t.isEmpty() ? null : t;
    }

    public static void fetchToken(Context c, TokenCallback cb) {
        JSONObject body = new JSONObject();
        try {
            body.put("app", VOICE_APP);
            body.put("lineId", Session.line(c));
        } catch (JSONException ignored) { }
        Api.post(c, "/voice/token", body, (res, err) -> {
            String token = tokenFrom(res);
            cb.done(token, token == null ? (err != null ? err : "The server sent no calling token.") : null);
        });
    }

    /** Registers for incoming calls. `done` may be null. */
    public static void register(Context c, @Nullable VoiceCallManager.Result done) {
        Context app = c.getApplicationContext();
        if (!Session.signedIn(app)) return;
        fetchToken(app, (token, err) -> {
            if (token == null) {
                if (done != null) done.done(false, err);
                return;
            }
            VoiceCallManager.get(app).register(token, (ok, error) -> { if (done != null) done.done(ok, error); });
        });
    }

    /** While the app is open, renew the registration before the token runs out. */
    public static void startRefresh(Context c) {
        Context app = c.getApplicationContext();
        stopRefresh();
        refresher = new Runnable() {
            @Override public void run() {
                register(app, null);
                MAIN.postDelayed(this, REFRESH_MS);
            }
        };
        MAIN.postDelayed(refresher, REFRESH_MS);
    }

    public static void stopRefresh() {
        if (refresher != null) MAIN.removeCallbacks(refresher);
        refresher = null;
    }
}

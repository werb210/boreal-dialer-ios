package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - sends this phone's Firebase token to the server (POST /api/staff/push-token,
// app "dialer-android"), so missed calls, voicemail, texts, client messages and Maya handoffs reach the lock screen
// like the iPhone dialler's alerts. Removed again on sign-out (DELETE, while the staff token still works).

import android.content.Context;
import android.util.Log;

import androidx.annotation.Nullable;

import com.google.firebase.messaging.FirebaseMessaging;

import org.json.JSONException;
import org.json.JSONObject;

public final class PushRegistrar {

    public static final String PUSH_APP = "dialer-android";

    private PushRegistrar() { }

    static JSONObject body(String token) {
        JSONObject o = new JSONObject();
        try {
            o.put("token", token.trim());
            o.put("app", PUSH_APP);
            o.put("environment", "production");
        } catch (JSONException ignored) { }
        return o;
    }

    /** Uploads the current Firebase token (force = even if it was sent before, e.g. after a new sign-in). */
    public static void upload(Context c, boolean force) {
        Context app = c.getApplicationContext();
        if (!Session.signedIn(app)) return;
        try {
            FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> {
                String token = task.isSuccessful() ? task.getResult() : null;
                if (token != null && !token.isEmpty()) send(app, token, force);
            });
        } catch (IllegalStateException e) {
            Log.w("Dialer", "Firebase is not set up in this build: no push alerts");
        }
    }

    static void send(Context app, String token, boolean force) {
        if (!force && token.equals(Session.pushToken(app))) return;
        Api.post(app, "/staff/push-token", body(token), (res, err) -> {
            if (err == null) Session.setPushToken(app, token);
            else Log.w("Dialer", "push token not saved: " + err);
        });
    }

    /** Sign-out: this phone stops getting this person's alerts. Calls `then` when done (or failed). */
    public static void remove(Context c, @Nullable Runnable then) {
        Context app = c.getApplicationContext();
        String token = Session.pushToken(app);
        if (token == null) { if (then != null) then.run(); return; }
        JSONObject o = new JSONObject();
        try { o.put("token", token); } catch (JSONException ignored) { }
        Api.delete(app, "/staff/push-token", o, (res, err) -> { if (then != null) then.run(); });
    }
}

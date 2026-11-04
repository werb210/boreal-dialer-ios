package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - the one HTTP client. Every request goes to the signed-in server with the staff token and
// the X-Silo line header (the iPhone dialler's APIClient). Requests run off the main thread; callbacks come back on
// it. A 401 signs the app out (the session expired or was revoked). Request URLs carry phone numbers and search
// text, so they are never logged.

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class Api {

    public interface Callback {
        void done(@Nullable JSONObject body, @Nullable String error);
    }

    public interface BytesCallback {
        void done(@Nullable byte[] body, @Nullable String error);
    }

    /** Called on the main thread when the server refuses the session. */
    public interface SignedOutListener {
        void onSignedOut();
    }

    private static final ExecutorService POOL = Executors.newFixedThreadPool(4);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final int TIMEOUT_MS = 20000;
    @Nullable private static SignedOutListener signedOutListener;

    private Api() { }

    public static void setSignedOutListener(@Nullable SignedOutListener l) { signedOutListener = l; }

    public static void get(Context c, String path, Callback cb) { json(c, "GET", path, null, true, cb); }

    public static void post(Context c, String path, @Nullable JSONObject body, Callback cb) { json(c, "POST", path, body, true, cb); }

    public static void delete(Context c, String path, @Nullable JSONObject body, Callback cb) { json(c, "DELETE", path, body, true, cb); }

    /** A request before sign-in (the text code), to the given server. */
    public static void postOpen(String url, @Nullable JSONObject body, Callback cb) {
        POOL.execute(() -> {
            Result r = run(url, "POST", body, null, null);
            MAIN.post(() -> cb.done(r.json(), r.error()));
        });
    }

    /** GET or POST a full URL with no session (the company directory). */
    public static void openRequest(String method, String url, @Nullable JSONObject body, Callback cb) {
        POOL.execute(() -> {
            Result r = run(url, method, body, null, null);
            MAIN.post(() -> cb.done(r.json(), r.error()));
        });
    }

    public static void bytes(Context c, String path, BytesCallback cb) {
        Context app = c.getApplicationContext();
        String base = Session.apiBase(app);
        String token = Session.token(app);
        if (base == null || token == null) { cb.done(null, "You're signed out. Sign in again."); return; }
        POOL.execute(() -> {
            Result r = run(base + path, "GET", null, token, Session.line(app));
            MAIN.post(() -> {
                if (r.status == 401) signOut();
                cb.done(r.error() == null ? r.body : null, r.error());
            });
        });
    }

    private static void json(Context c, String method, String path, @Nullable JSONObject body, boolean auth, Callback cb) {
        Context app = c.getApplicationContext();
        String base = Session.apiBase(app);
        String token = auth ? Session.token(app) : null;
        if (base == null || (auth && token == null)) { cb.done(null, "You're signed out. Sign in again."); return; }
        POOL.execute(() -> {
            Result r = run(base + path, method, body, token, Session.line(app));
            MAIN.post(() -> {
                if (r.status == 401 && auth) signOut();
                cb.done(r.json(), r.error());
            });
        });
    }

    private static void signOut() {
        SignedOutListener l = signedOutListener;
        if (l != null) l.onSignedOut();
    }

    static final class Result {
        int status;
        byte[] body = new byte[0];

        @Nullable JSONObject json() {
            if (body.length == 0) return new JSONObject();
            try {
                return new JSONObject(new String(body, StandardCharsets.UTF_8));
            } catch (JSONException e) {
                return null;
            }
        }

        @Nullable String error() {
            if (status >= 200 && status < 300) return null;
            String code = null;
            String message = null;
            JSONObject o = status == 0 ? null : json();
            if (o != null) {
                message = o.optString("message", null);
                Object e = o.opt("error");
                if (e instanceof String) code = (String) e;
                else if (e instanceof JSONObject) {
                    code = ((JSONObject) e).optString("code", null);
                    if (message == null) message = ((JSONObject) e).optString("message", null);
                } else code = o.optString("code", null);
            }
            return ApiErrors.message(status, code, message);
        }
    }

    @NonNull
    private static Result run(String url, String method, @Nullable JSONObject body, @Nullable String token, @Nullable String line) {
        Result r = new Result();
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestMethod(method);
            conn.setConnectTimeout(TIMEOUT_MS);
            conn.setReadTimeout(TIMEOUT_MS);
            conn.setRequestProperty("Accept", "application/json");
            if (line != null) conn.setRequestProperty("X-Silo", line);
            if (token != null) conn.setRequestProperty("Authorization", "Bearer " + token);
            if (body != null) {
                byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
                conn.setDoOutput(true);
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setFixedLengthStreamingMode(bytes.length);
                try (OutputStream out = conn.getOutputStream()) { out.write(bytes); }
            }
            r.status = conn.getResponseCode();
            InputStream in = r.status >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (in != null) {
                try (InputStream s = in) { r.body = readAll(s); }
            }
        } catch (IOException | RuntimeException e) {
            r.status = 0;
        } finally {
            if (conn != null) conn.disconnect();
        }
        return r;
    }

    private static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[16384];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        return out.toByteArray();
    }
}

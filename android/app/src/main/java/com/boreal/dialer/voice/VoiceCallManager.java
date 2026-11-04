package com.boreal.dialer.voice;

// BOREAL_ANDROID_DIALER_v1 - the Android dialler's calling engine (Twilio Voice Android SDK). It first lived in the Android
// staff portal; the portal now hands calls to this app, so one phone has one calling engine and never rings twice.
//
// The Android twin of the iPhone dialler's call engine:
//   - registers this phone/tablet with Twilio for incoming calls using the FCM token (Twilio sends an FCM data
//     message for every incoming call; DialerMessagingService hands it to handleFcm()),
//   - rings through Android Telecom as a self-managed ConnectionService, so the call rings on the lock screen,
//     works with Bluetooth headsets and car kits, and Android treats the app as a calling app,
//   - places outgoing calls with the same parameters as the iPhone dialler (To = the E.164 number),
//   - keeps the call alive in a foreground service (VoiceCallService) when the screen is off.
// One call at a time: a second invite while busy is declined, so Twilio's voicemail/next-agent logic takes over.
//
// Everything runs on the main thread (the Twilio SDK needs a Looper thread); callers from other threads are posted.

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.telecom.CallAudioState;
import android.telecom.DisconnectCause;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.google.firebase.messaging.FirebaseMessaging;
import com.twilio.voice.Call;
import com.twilio.voice.CallException;
import com.twilio.voice.CallInvite;
import com.twilio.voice.CancelledCallInvite;
import com.twilio.voice.ConnectOptions;
import com.twilio.voice.MessageListener;
import com.twilio.voice.RegistrationException;
import com.twilio.voice.RegistrationListener;
import com.twilio.voice.UnregistrationListener;
import com.twilio.voice.Voice;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;

public final class VoiceCallManager {

    private static final String TAG = "DialerVoice";
    private static final String PREFS = "dialer_voice";
    private static final String KEY_ACCESS_TOKEN = "access_token";
    private static final String KEY_REGISTERED_FCM = "registered_fcm";

    /** Receives every engine event (the app's screens and the call screen). */
    public interface Listener {
        void onVoiceEvent(@NonNull String event, @NonNull JSONObject data);
    }

    public interface Result {
        void done(boolean ok, @Nullable String error);
    }

    /** The one call this device is ringing or on. */
    public static final class CallSession {
        public final String uuid;
        public final boolean outgoing;
        public String callSid = "";
        public String from = "";
        public String callerName = "";
        public String phase = "ringing"; // ringing | connecting | connected
        public long connectedAt = 0L;
        @Nullable public CallInvite invite;
        @Nullable public Call call;
        @Nullable public VoiceConnection connection;
        @Nullable Map<String, String> params;
        @Nullable String accessToken;
        boolean ended = false;

        CallSession(String uuid, boolean outgoing) {
            this.uuid = uuid;
            this.outgoing = outgoing;
        }

        /** What the screens show: the name the server sent, else the number, else "Unknown caller". */
        public String label() {
            if (callerName != null && !callerName.trim().isEmpty()) return callerName.trim();
            String f = from == null ? "" : from.replaceFirst("^client:", "").trim();
            return f.isEmpty() ? "Unknown caller" : f;
        }
    }

    private static VoiceCallManager instance;

    public static synchronized VoiceCallManager get(@NonNull Context context) {
        if (instance == null) instance = new VoiceCallManager(context.getApplicationContext());
        return instance;
    }

    private final Context app;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final CopyOnWriteArrayList<Listener> listeners = new CopyOnWriteArrayList<>();
    private final SharedPreferences prefs;

    private boolean registered = false;
    @Nullable private String fcmToken;
    @Nullable private String lastError;
    @Nullable private CallSession current;
    private boolean muted = false;
    private boolean speaker = false;

    private VoiceCallManager(Context app) {
        this.app = app;
        this.prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    // ---------------------------------------------------------------- listeners

    public void addListener(@NonNull Listener l) { listeners.addIfAbsent(l); }

    public void removeListener(@NonNull Listener l) { listeners.remove(l); }

    private void emit(String event, JSONObject data) {
        for (Listener l : listeners) {
            try { l.onVoiceEvent(event, data); } catch (RuntimeException e) { Log.w(TAG, "listener failed: " + e.getMessage()); }
        }
    }

    private static JSONObject obj(Object... kv) {
        JSONObject o = new JSONObject();
        for (int i = 0; i + 1 < kv.length; i += 2) {
            try { o.put(String.valueOf(kv[i]), kv[i + 1] == null ? JSONObject.NULL : kv[i + 1]); } catch (JSONException ignored) { }
        }
        return o;
    }

    private JSONObject callJson(CallSession s) {
        return obj("uuid", s.uuid, "callSid", s.callSid, "from", s.from, "callerName", s.callerName, "phase", s.phase,
                "outgoing", s.outgoing);
    }

    private void emitState(CallSession s, String state, @Nullable String reason) {
        JSONObject o = obj("state", state, "from", s.from, "uuid", s.uuid, "callerName", s.callerName);
        if (reason != null) { try { o.put("reason", reason); } catch (JSONException ignored) { } }
        emit("callStateChanged", o);
    }

    private void onMain(Runnable r) {
        if (Looper.myLooper() == Looper.getMainLooper()) r.run(); else main.post(r);
    }

    // ---------------------------------------------------------------- state

    @Nullable public CallSession current() { return current; }

    public boolean isMuted() { return muted; }

    public boolean isSpeaker() { return speaker; }

    public boolean isRegistered() { return registered; }

    @Nullable public String lastError() { return lastError; }

    public JSONObject stateJson() {
        JSONObject o = obj("registered", registered, "hasDeviceToken", fcmToken != null && !fcmToken.isEmpty(),
                "muted", muted, "speaker", speaker);
        try {
            if (lastError != null) o.put("lastError", lastError);
            if (current != null) o.put("call", callJson(current));
        } catch (JSONException ignored) { }
        return o;
    }

    @Nullable String storedAccessToken() { return prefs.getString(KEY_ACCESS_TOKEN, null); }

    // ---------------------------------------------------------------- registration

    /** Registers this device for incoming calls under the staff member's identity (the token's identity). */
    public void register(@NonNull String accessToken, @NonNull Result result) {
        prefs.edit().putString(KEY_ACCESS_TOKEN, accessToken).apply();
        TelecomHelper.ensureAccount(app);
        try {
            FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> onMain(() -> {
                if (!task.isSuccessful() || task.getResult() == null || task.getResult().isEmpty()) {
                    String why = task.getException() != null ? task.getException().getMessage() : "no_fcm_token";
                    setRegistered(false, "fcm_token_unavailable: " + why);
                    result.done(false, lastError);
                    return;
                }
                fcmToken = task.getResult();
                registerWithTwilio(accessToken, fcmToken, result);
            }));
        } catch (IllegalStateException e) {
            // Firebase is not configured in this build (no google-services.json, e.g. a pull-request build): outgoing
            // calls work, incoming calls cannot ring.
            setRegistered(false, "firebase_not_configured");
            result.done(false, lastError);
        }
    }

    private void registerWithTwilio(String accessToken, String token, Result result) {
        Voice.register(accessToken, Voice.RegistrationChannel.FCM, token, new RegistrationListener() {
            @Override
            public void onRegistered(@NonNull String a, @NonNull String fcm) {
                onMain(() -> {
                    prefs.edit().putString(KEY_REGISTERED_FCM, fcm).apply();
                    setRegistered(true, null);
                    result.done(true, null);
                });
            }

            @Override
            public void onError(@NonNull RegistrationException error, @NonNull String a, @NonNull String fcm) {
                onMain(() -> {
                    setRegistered(false, "twilio_register_" + error.getErrorCode() + ": " + error.getMessage());
                    result.done(false, lastError);
                });
            }
        });
    }

    private void setRegistered(boolean value, @Nullable String error) {
        boolean changed = registered != value;
        registered = value;
        lastError = error;
        if (error != null) Log.w(TAG, error);
        if (changed || error != null) emit("registrationChanged", obj("registered", value, "error", error));
    }

    /** Sign-out: this device stops ringing for the signed-out person. */
    public void unregister() {
        String token = storedAccessToken();
        String fcm = prefs.getString(KEY_REGISTERED_FCM, fcmToken);
        prefs.edit().remove(KEY_ACCESS_TOKEN).remove(KEY_REGISTERED_FCM).apply();
        if (token != null && fcm != null) {
            Voice.unregister(token, Voice.RegistrationChannel.FCM, fcm, new UnregistrationListener() {
                @Override public void onUnregistered(@Nullable String a, @Nullable String f) { }
                @Override public void onError(@NonNull RegistrationException e, @Nullable String a, @Nullable String f) {
                    Log.w(TAG, "unregister failed: " + e.getMessage());
                }
            });
        }
        setRegistered(false, null);
    }

    /** FCM rotated the token: register again with the last access token so calls keep ringing. */
    public void onFcmToken(@NonNull String token) {
        onMain(() -> {
            fcmToken = token;
            String access = storedAccessToken();
            if (access != null) registerWithTwilio(access, token, (ok, err) -> { });
        });
    }

    // ---------------------------------------------------------------- incoming

    /** True when the FCM message was a Twilio call message (and was handled). */
    public boolean handleFcm(@NonNull Map<String, String> data) {
        if (data.isEmpty()) return false;
        return Voice.handleMessage(app, data, new MessageListener() {
            @Override
            public void onCallInvite(@NonNull CallInvite invite) {
                onMain(() -> onIncoming(invite));
            }

            @Override
            public void onCancelledCallInvite(@NonNull CancelledCallInvite cancelled, @Nullable CallException error) {
                onMain(() -> onCancelled(cancelled.getCallSid()));
            }
        });
    }

    private void onIncoming(CallInvite invite) {
        if (current != null) {
            // Busy: decline, so the server's routing (voicemail, next staff member) carries on.
            invite.reject(app);
            return;
        }
        CallSession s = new CallSession(UUID.randomUUID().toString(), false);
        s.invite = invite;
        s.callSid = invite.getCallSid();
        s.from = invite.getFrom() == null ? "" : invite.getFrom();
        Map<String, String> custom = invite.getCustomParameters();
        String name = custom == null ? null : custom.get("callerName");
        s.callerName = name == null ? "" : name;
        s.phase = "ringing";
        current = s;
        if (!TelecomHelper.addIncoming(app, s)) {
            // Telecom refused (for example a cellular call is in progress on some devices): ring with our own
            // notification and full-screen call screen instead.
            CallNotifications.showIncoming(app, s);
        }
        emit("callIncoming", callJson(s));
        emitState(s, "ringing", null);
    }

    private void onCancelled(String callSid) {
        CallSession s = current;
        if (s == null || s.outgoing || s.call != null || !callSid.equals(s.callSid)) return;
        end(s, "missed", DisconnectCause.MISSED);
    }

    /** Answer (from the call screen, the notification, a headset or Telecom). */
    public void answer(@Nullable String uuid) {
        onMain(() -> {
            CallSession s = current;
            if (s == null || s.invite == null || s.call != null || (uuid != null && !uuid.isEmpty() && !uuid.equals(s.uuid))) return;
            CallNotifications.cancelIncoming(app);
            s.phase = "connecting";
            s.call = s.invite.accept(app, listenerFor(s));
            if (s.connection != null) s.connection.setActive();
            VoiceCallService.start(app);
            emit("callAnswered", callJson(s));
            emitState(s, "connecting", null);
        });
    }

    /** Decline a ringing call. */
    public void reject(@Nullable String uuid) {
        onMain(() -> {
            CallSession s = current;
            if (s == null || (uuid != null && !uuid.isEmpty() && !uuid.equals(s.uuid))) return;
            if (s.call == null && s.invite != null) {
                s.invite.reject(app);
                end(s, "declined", DisconnectCause.REJECTED);
            } else {
                hangup();
            }
        });
    }

    // ---------------------------------------------------------------- outgoing

    /** Places a call (params: To = the E.164 number, as the iPhone dialler sends). */
    public void connect(@Nullable String accessToken, @NonNull Map<String, String> params, @NonNull String label,
                        @NonNull Result result) {
        onMain(() -> {
            if (current != null) { result.done(false, "busy"); return; }
            String token = accessToken != null && !accessToken.isEmpty() ? accessToken : storedAccessToken();
            if (token == null) { result.done(false, "no_voice_token"); return; }
            if (accessToken != null && !accessToken.isEmpty()) prefs.edit().putString(KEY_ACCESS_TOKEN, accessToken).apply();
            CallSession s = new CallSession(UUID.randomUUID().toString(), true);
            s.params = new HashMap<>(params);
            s.accessToken = token;
            // Telecom gets the number; the screens show the label (the contact's name, or the number).
            String to = params.get("To");
            s.from = to != null && !to.isEmpty() ? to : label;
            s.callerName = label;
            s.phase = "connecting";
            current = s;
            if (!TelecomHelper.placeOutgoing(app, s)) startOutgoingTwilio(s.uuid);
            result.done(true, null);
            emitState(s, "connecting", null);
        });
    }

    /** Telecom created the outgoing connection (or refused it): start the Twilio call. */
    void startOutgoingTwilio(String uuid) {
        onMain(() -> {
            CallSession s = current;
            if (s == null || !s.uuid.equals(uuid) || s.call != null || s.accessToken == null) return;
            ConnectOptions options = new ConnectOptions.Builder(s.accessToken)
                    .params(s.params == null ? new HashMap<>() : s.params)
                    .build();
            s.call = Voice.connect(app, options, listenerFor(s));
            VoiceCallService.start(app);
        });
    }

    // ---------------------------------------------------------------- in call

    private Call.Listener listenerFor(CallSession s) {
        return new Call.Listener() {
            @Override public void onRinging(@NonNull Call call) {
                if (call.getSid() != null) s.callSid = call.getSid();
            }

            @Override public void onConnectFailure(@NonNull Call call, @NonNull CallException error) {
                Log.w(TAG, "connect failed " + error.getErrorCode() + ": " + error.getMessage());
                end(s, "failed: " + error.getMessage(), DisconnectCause.ERROR);
            }

            @Override public void onConnected(@NonNull Call call) {
                if (call.getSid() != null) s.callSid = call.getSid();
                s.phase = "connected";
                s.connectedAt = System.currentTimeMillis();
                if (s.connection != null) s.connection.setActive();
                call.mute(muted);
                VoiceCallService.update(app);
                emit("callConnected", callJson(s));
                emitState(s, "connected", null);
            }

            @Override public void onReconnecting(@NonNull Call call, @NonNull CallException error) {
                emit("callReconnecting", callJson(s));
            }

            @Override public void onReconnected(@NonNull Call call) {
                emit("callReconnected", callJson(s));
            }

            @Override public void onDisconnected(@NonNull Call call, @Nullable CallException error) {
                end(s, error == null ? "ended" : "dropped: " + error.getMessage(),
                        error == null ? DisconnectCause.LOCAL : DisconnectCause.ERROR);
            }
        };
    }

    public void hangup() {
        onMain(() -> {
            CallSession s = current;
            if (s == null) return;
            if (s.call != null) {
                s.call.disconnect(); // onDisconnected ends the session
                main.postDelayed(() -> { if (current == s) end(s, "ended", DisconnectCause.LOCAL); }, 3000);
            } else if (s.invite != null) {
                s.invite.reject(app);
                end(s, "declined", DisconnectCause.REJECTED);
            } else {
                end(s, "cancelled", DisconnectCause.CANCELED);
            }
        });
    }

    public boolean mute(boolean value) {
        muted = value;
        CallSession s = current;
        if (s != null && s.call != null) s.call.mute(value);
        emit("callMuted", obj("muted", value, "uuid", s == null ? "" : s.uuid));
        return muted;
    }

    @SuppressWarnings("deprecation")
    public boolean speaker(boolean on) {
        CallSession s = current;
        if (s != null && s.connection != null) {
            s.connection.setAudioRoute(on ? CallAudioState.ROUTE_SPEAKER : CallAudioState.ROUTE_WIRED_OR_EARPIECE);
        } else {
            android.media.AudioManager am = (android.media.AudioManager) app.getSystemService(Context.AUDIO_SERVICE);
            if (am != null) {
                am.setMode(android.media.AudioManager.MODE_IN_COMMUNICATION);
                am.setSpeakerphoneOn(on);
            }
        }
        speaker = on;
        return speaker;
    }

    public void sendDigits(@NonNull String digits) {
        CallSession s = current;
        if (s != null && s.call != null && !digits.isEmpty()) s.call.sendDigits(digits);
    }

    // ---------------------------------------------------------------- telecom callbacks

    void attachConnection(String uuid, VoiceConnection connection) {
        CallSession s = current;
        if (s != null && s.uuid.equals(uuid)) s.connection = connection;
        else connection.destroyWith(DisconnectCause.CANCELED);
    }

    /** Telecom reports the audio route or mute changed (headset button, car kit, system UI). */
    void onAudioState(@Nullable CallAudioState state) {
        if (state == null) return;
        speaker = state.getRoute() == CallAudioState.ROUTE_SPEAKER;
        if (state.isMuted() != muted) mute(state.isMuted());
    }

    /** Telecom could not create the incoming connection: fall back to our own ringing notification. */
    void onIncomingTelecomFailed(String uuid) {
        CallSession s = current;
        if (s != null && s.uuid.equals(uuid) && s.call == null) CallNotifications.showIncoming(app, s);
    }

    // ---------------------------------------------------------------- end

    private void end(CallSession s, String reason, int cause) {
        if (s.ended) return;
        s.ended = true;
        if (s.connection != null) s.connection.destroyWith(cause);
        if (current == s) current = null;
        muted = false;
        speaker = false;
        CallNotifications.cancelIncoming(app);
        VoiceCallService.stop(app);
        emit("callEnded", obj("uuid", s.uuid, "from", s.from, "callerName", s.callerName, "reason", reason));
        emitState(s, "ended", reason);
        app.sendBroadcast(new Intent(CallActivity.ACTION_CLOSE).setPackage(app.getPackageName()));
    }
}

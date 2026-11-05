package com.boreal.dialer.voice;

// BOREAL_ANDROID_DIALER_v1 - registers the app with Android Telecom as a self-managed calling app (the Android
// equivalent of CallKit) and hands it incoming and outgoing calls. Every method returns false instead of throwing,
// so a device that refuses (old firmware, a cellular call in progress) falls back to the app's own call screen.

import android.content.ComponentName;
import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.telecom.PhoneAccount;
import android.telecom.PhoneAccountHandle;
import android.telecom.TelecomManager;
import android.util.Log;

import com.boreal.dialer.R;

final class TelecomHelper {

    static final String EXTRA_UUID = "dialer_call_uuid";
    private static final String ACCOUNT_ID = "staff-voice";

    private TelecomHelper() { }

    static PhoneAccountHandle handle(Context c) {
        return new PhoneAccountHandle(new ComponentName(c, VoiceConnectionService.class), ACCOUNT_ID);
    }

    private static TelecomManager telecom(Context c) {
        return (TelecomManager) c.getSystemService(Context.TELECOM_SERVICE);
    }

    static boolean ensureAccount(Context c) {
        try {
            TelecomManager tm = telecom(c);
            if (tm == null) return false;
            PhoneAccount account = PhoneAccount.builder(handle(c), c.getString(R.string.app_name))
                    .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                    .addSupportedUriScheme(PhoneAccount.SCHEME_TEL)
                    .addSupportedUriScheme(PhoneAccount.SCHEME_SIP)
                    .build();
            tm.registerPhoneAccount(account);
            return true;
        } catch (RuntimeException e) {
            Log.w("DialerVoice", "phone account: " + e.getMessage());
            return false;
        }
    }

    private static Uri address(String raw) {
        String value = raw == null ? "" : raw.replaceFirst("^client:", "").trim();
        boolean phone = value.matches("^\\+?[0-9]{5,16}$");
        return Uri.fromParts(phone ? PhoneAccount.SCHEME_TEL : PhoneAccount.SCHEME_SIP, value.isEmpty() ? "unknown" : value, null);
    }

    static boolean addIncoming(Context c, VoiceCallManager.CallSession s) {
        try {
            TelecomManager tm = telecom(c);
            if (tm == null || !ensureAccount(c)) return false;
            if (!tm.isIncomingCallPermitted(handle(c))) return false;
            Bundle extras = new Bundle();
            extras.putString(EXTRA_UUID, s.uuid);
            extras.putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, address(s.from));
            tm.addNewIncomingCall(handle(c), extras);
            return true;
        } catch (RuntimeException e) {
            Log.w("DialerVoice", "incoming via telecom: " + e.getMessage());
            return false;
        }
    }

    static boolean placeOutgoing(Context c, VoiceCallManager.CallSession s) {
        try {
            TelecomManager tm = telecom(c);
            if (tm == null || !ensureAccount(c)) return false;
            if (!tm.isOutgoingCallPermitted(handle(c))) return false;
            Bundle callExtras = new Bundle();
            callExtras.putString(EXTRA_UUID, s.uuid);
            Bundle extras = new Bundle();
            extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle(c));
            extras.putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, callExtras);
            tm.placeCall(address(s.from), extras);
            return true;
        } catch (RuntimeException e) {
            Log.w("DialerVoice", "outgoing via telecom: " + e.getMessage());
            return false;
        }
    }
}

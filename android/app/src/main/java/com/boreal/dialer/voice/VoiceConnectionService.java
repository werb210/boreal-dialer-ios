package com.boreal.dialer.voice;

// BOREAL_ANDROID_DIALER_v1 - Android Telecom asks this service for the Connection that represents a call.

import android.os.Bundle;
import android.telecom.Connection;
import android.telecom.ConnectionRequest;
import android.telecom.ConnectionService;
import android.telecom.PhoneAccountHandle;
import android.telecom.TelecomManager;

public class VoiceConnectionService extends ConnectionService {

    private static String uuidOf(ConnectionRequest request) {
        Bundle extras = request == null ? null : request.getExtras();
        if (extras == null) return "";
        String direct = extras.getString(TelecomHelper.EXTRA_UUID);
        if (direct != null) return direct;
        for (String key : new String[] { TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, TelecomManager.EXTRA_INCOMING_CALL_EXTRAS }) {
            Bundle nested = extras.getBundle(key);
            String fromNested = nested == null ? null : nested.getString(TelecomHelper.EXTRA_UUID);
            if (fromNested != null) return fromNested;
        }
        return "";
    }

    private VoiceConnection build(ConnectionRequest request) {
        VoiceCallManager manager = VoiceCallManager.get(this);
        String uuid = uuidOf(request);
        // Some devices drop the extras: the one call this app is setting up is the current one.
        VoiceCallManager.CallSession pending = manager.current();
        if (uuid.isEmpty() && pending != null && pending.connection == null) uuid = pending.uuid;
        VoiceConnection connection = new VoiceConnection(this, uuid);
        VoiceCallManager.CallSession s = manager.current();
        if (s != null && s.uuid.equals(uuid)) {
            connection.setAddress(request.getAddress(), TelecomManager.PRESENTATION_ALLOWED);
            connection.setCallerDisplayName(s.label(), TelecomManager.PRESENTATION_ALLOWED);
        }
        manager.attachConnection(uuid, connection);
        return connection;
    }

    @Override
    public Connection onCreateIncomingConnection(PhoneAccountHandle account, ConnectionRequest request) {
        VoiceConnection connection = build(request);
        connection.setRinging();
        return connection;
    }

    @Override
    public void onCreateIncomingConnectionFailed(PhoneAccountHandle account, ConnectionRequest request) {
        VoiceCallManager.get(this).onIncomingTelecomFailed(uuidOf(request));
    }

    @Override
    public Connection onCreateOutgoingConnection(PhoneAccountHandle account, ConnectionRequest request) {
        VoiceConnection connection = build(request);
        connection.setDialing();
        VoiceCallManager.get(this).startOutgoingTwilio(connection.uuid());
        return connection;
    }

    @Override
    public void onCreateOutgoingConnectionFailed(PhoneAccountHandle account, ConnectionRequest request) {
        // Telecom said no (for example during a cellular call): the call still goes out, without Telecom.
        VoiceCallManager.get(this).startOutgoingTwilio(uuidOf(request));
    }
}

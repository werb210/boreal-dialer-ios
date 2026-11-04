package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - the link the staff portal opens to start a call here (CROSS_PLATFORM_DIALER_CONTRACT.md):
//   <scheme>://call?phone=<percent-encoded E.164>   or   <scheme>://call?contactId=<id>
// start=true is the only request to call straight away; otherwise the number is put on the keypad to confirm.
// Unknown routes or keys, duplicate keys, malformed phones and ids over 128 characters are refused. tel: links (a
// number tapped in another app) are put on the keypad.

import androidx.annotation.Nullable;

import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import java.util.HashMap;
import java.util.Map;

public final class DeepLinks {

    public static final class Target {
        @Nullable public final String phone;
        @Nullable public final String contactId;
        public final boolean start;

        Target(@Nullable String phone, @Nullable String contactId, boolean start) {
            this.phone = phone;
            this.contactId = contactId;
            this.start = start;
        }
    }

    private DeepLinks() { }

    @Nullable
    public static Target parse(@Nullable String uri, String scheme) {
        if (uri == null) return null;
        String s = uri.trim();
        if (s.regionMatches(true, 0, "tel:", 0, 4)) {
            String phone = PhoneNumbers.e164(decode(s.substring(4)));
            return phone == null ? null : new Target(phone, null, false);
        }
        String prefix = scheme + "://call";
        if (!s.regionMatches(true, 0, prefix, 0, prefix.length())) return null;
        String rest = s.substring(prefix.length());
        if (rest.startsWith("/")) rest = rest.substring(1);
        if (rest.isEmpty() || rest.charAt(0) != '?') return null;
        Map<String, String> params = new HashMap<>();
        for (String pair : rest.substring(1).split("&")) {
            if (pair.isEmpty()) continue;
            int eq = pair.indexOf('=');
            if (eq <= 0) return null;
            String key = pair.substring(0, eq);
            String value = decode(pair.substring(eq + 1));
            if (value == null) return null;
            if (!key.equals("phone") && !key.equals("contactId") && !key.equals("start")) return null;
            if (params.containsKey(key)) return null;
            params.put(key, value);
        }
        String phoneRaw = params.get("phone");
        String contactId = params.get("contactId");
        String startRaw = params.get("start");
        if (startRaw != null && !startRaw.equals("true") && !startRaw.equals("false")) return null;
        boolean start = "true".equals(startRaw);
        if ((phoneRaw == null) == (contactId == null)) return null; // exactly one of them
        if (phoneRaw != null) {
            String phone = PhoneNumbers.e164(phoneRaw);
            if (phone == null || !phoneRaw.trim().startsWith("+")) return null;
            return new Target(phone, null, start);
        }
        String id = contactId.trim();
        if (id.isEmpty() || id.length() > 128 || !id.matches("^[A-Za-z0-9_-]+$")) return null;
        return new Target(null, id, start);
    }

    @Nullable
    private static String decode(String raw) {
        try {
            return URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8");
        } catch (UnsupportedEncodingException | IllegalArgumentException e) {
            return null;
        }
    }
}

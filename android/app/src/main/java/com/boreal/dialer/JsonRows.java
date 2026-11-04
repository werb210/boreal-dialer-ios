package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - reading list replies. The servers answer with { items }, { data } or { conversations }
// depending on the route; a missing or null field reads as "".

import androidx.annotation.Nullable;

import org.json.JSONArray;
import org.json.JSONObject;

final class JsonRows {

    private JsonRows() { }

    static JSONArray list(@Nullable JSONObject body, String... keys) {
        if (body == null) return new JSONArray();
        for (String k : keys) {
            JSONArray a = body.optJSONArray(k);
            if (a != null) return a;
            JSONObject nested = body.optJSONObject(k);
            if (nested != null) {
                for (String inner : keys) {
                    JSONArray b = nested.optJSONArray(inner);
                    if (b != null) return b;
                }
            }
        }
        return new JSONArray();
    }

    static String str(@Nullable JSONObject o, String key) {
        if (o == null || o.isNull(key)) return "";
        return o.optString(key, "").trim();
    }

    static int num(@Nullable JSONObject o, String key) {
        if (o == null || o.isNull(key)) return 0;
        Object v = o.opt(key);
        if (v instanceof Number) return ((Number) v).intValue();
        try { return Integer.parseInt(String.valueOf(v).trim()); } catch (NumberFormatException e) { return 0; }
    }

    /** A contact's name the way the iPhone dialler shows it. */
    static String contactName(JSONObject c) {
        String name = str(c, "name");
        if (!name.isEmpty()) return name;
        String joined = (str(c, "first_name") + " " + str(c, "last_name")).trim();
        if (!joined.isEmpty()) return joined;
        if (!str(c, "email").isEmpty()) return str(c, "email");
        if (!str(c, "phone").isEmpty()) return PhoneNumbers.display(str(c, "phone"));
        return "Unnamed contact";
    }
}

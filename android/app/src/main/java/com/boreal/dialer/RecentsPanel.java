package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - recent calls from the server (GET /api/voice/recent-calls -> { items }), so calls taken on
// the iPhone, the portal or this phone all show. Missed calls are red. Tap to call back; hold for Call or Text.

import android.app.Activity;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class RecentsPanel extends ListPanel {

    private static final Set<String> MISSED = new HashSet<>(Arrays.asList(
            "missed", "no-answer", "no_answer", "busy", "canceled", "cancelled", "failed", "voicemail"));

    RecentsPanel(Activity activity) { super(activity, false); }

    static boolean missed(String direction, String status) {
        String d = direction.toLowerCase();
        return (d.startsWith("in") || d.isEmpty()) && MISSED.contains(status.toLowerCase());
    }

    @Override
    protected void load(int g) {
        Api.get(activity, "/voice/recent-calls", (res, err) -> {
            if (err != null) { showError(g, err); return; }
            JSONArray items = JsonRows.list(res, "items", "data", "calls");
            List<RowAdapter.Row> rows = new ArrayList<>();
            for (int i = 0; i < items.length(); i++) {
                JSONObject c = items.optJSONObject(i);
                if (c == null) continue;
                String phone = JsonRows.str(c, "phone_number");
                String name = JsonRows.str(c, "contact_name");
                String direction = JsonRows.str(c, "direction");
                String status = JsonRows.str(c, "status");
                boolean isMissed = missed(direction, status);
                String kind = isMissed ? "Missed call" : direction.toLowerCase().startsWith("out") ? "Outgoing" : "Incoming";
                String duration = TimeText.duration(JsonRows.num(c, "duration_seconds"));
                String title = name.isEmpty() ? (phone.isEmpty() ? "Unknown caller" : PhoneNumbers.display(phone)) : name;
                String subtitle = duration.isEmpty() ? kind : kind + " · " + duration;
                if (!name.isEmpty() && !phone.isEmpty()) subtitle = PhoneNumbers.display(phone) + " · " + subtitle;
                rows.add(new RowAdapter.Row(title, subtitle, TimeText.shortText(JsonRows.str(c, "created_at")), isMissed, false, c));
            }
            show(g, rows);
        });
    }

    @Override
    protected void onTap(RowAdapter.Row row) {
        JSONObject c = (JSONObject) row.item;
        String phone = JsonRows.str(c, "phone_number");
        if (PhoneNumbers.e164(phone) == null) { Ui.toast(activity, "There's no number to call back."); return; }
        Calls.start(activity, phone, JsonRows.str(c, "contact_name"));
    }

    @Override
    protected void onLongPress(RowAdapter.Row row) {
        JSONObject c = (JSONObject) row.item;
        String contactId = JsonRows.str(c, "contact_id");
        callOrText(row.title, JsonRows.str(c, "phone_number"), contactId.isEmpty() ? null : contactId);
    }
}

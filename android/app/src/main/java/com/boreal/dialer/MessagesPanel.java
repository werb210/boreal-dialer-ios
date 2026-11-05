package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - text-message conversations (GET /api/communications/sms?q= -> { conversations }). Unread
// conversations are bold. Tap to open the thread.

import android.app.Activity;
import android.net.Uri;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

final class MessagesPanel extends ListPanel {

    MessagesPanel(Activity activity) { super(activity, true); }

    @Override
    protected void load(int g) {
        String q = query();
        String path = q.isEmpty() ? "/communications/sms" : "/communications/sms?q=" + Uri.encode(q);
        Api.get(activity, path, (res, err) -> {
            if (err != null) { showError(g, err); return; }
            JSONArray items = JsonRows.list(res, "conversations", "data", "items");
            List<RowAdapter.Row> rows = new ArrayList<>();
            for (int i = 0; i < items.length(); i++) {
                JSONObject t = items.optJSONObject(i);
                if (t == null) continue;
                String name = JsonRows.str(t, "display_name");
                String phone = JsonRows.str(t, "phone");
                String title = name.isEmpty() ? PhoneNumbers.display(phone) : name;
                if (title.isEmpty()) title = "Unknown";
                boolean unread = JsonRows.num(t, "unread_count") > 0;
                rows.add(new RowAdapter.Row(title, JsonRows.str(t, "last_body"), TimeText.shortText(JsonRows.str(t, "last_at")),
                        false, unread, t));
            }
            show(g, rows);
        });
    }

    @Override
    protected void onTap(RowAdapter.Row row) {
        JSONObject t = (JSONObject) row.item;
        String contactId = JsonRows.str(t, "contact_id");
        activity.startActivity(ThreadActivity.intent(activity, contactId.isEmpty() ? null : contactId,
                JsonRows.str(t, "phone"), row.title));
    }
}

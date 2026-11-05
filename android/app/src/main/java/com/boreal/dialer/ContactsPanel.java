package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - contact lookup in the CRM (GET /api/crm/contacts?pageSize=25&q=... -> { data }). Tap a
// contact to call or text them.

import android.app.Activity;
import android.net.Uri;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

final class ContactsPanel extends ListPanel {

    ContactsPanel(Activity activity) { super(activity, true); }

    @Override
    protected void load(int g) {
        String q = query();
        String path = q.isEmpty() ? "/crm/contacts?pageSize=50" : "/crm/contacts?pageSize=25&q=" + Uri.encode(q);
        Api.get(activity, path, (res, err) -> {
            if (err != null) { showError(g, err); return; }
            JSONArray items = JsonRows.list(res, "data", "items", "contacts");
            List<RowAdapter.Row> rows = new ArrayList<>();
            for (int i = 0; i < items.length(); i++) {
                JSONObject c = items.optJSONObject(i);
                if (c == null) continue;
                String phone = JsonRows.str(c, "phone");
                String company = JsonRows.str(c, "company_name");
                String subtitle = PhoneNumbers.display(phone);
                if (!company.isEmpty()) subtitle = subtitle.isEmpty() ? company : subtitle + " · " + company;
                rows.add(new RowAdapter.Row(JsonRows.contactName(c), subtitle, "", false, false, c));
            }
            show(g, rows);
        });
    }

    @Override
    protected void onTap(RowAdapter.Row row) {
        JSONObject c = (JSONObject) row.item;
        String id = JsonRows.str(c, "id");
        callOrText(row.title, JsonRows.str(c, "phone"), id.isEmpty() ? null : id);
    }
}

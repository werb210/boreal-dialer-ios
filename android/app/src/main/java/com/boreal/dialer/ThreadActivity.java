package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - one text conversation, like the iPhone dialler's SMS thread:
//   GET  /api/communications/sms/thread?contactId=... (or phone=...) -> { messages }
//   POST /api/communications/sms { to, body, contactId? }
//   POST /api/communications/messages/mark-read { contactId | phone }

import android.content.Context;
import android.content.Intent;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

public class ThreadActivity extends AppCompatActivity {

    private static final String EXTRA_CONTACT = "contactId";
    private static final String EXTRA_PHONE = "phone";
    private static final String EXTRA_NAME = "name";

    @Nullable private String contactId;
    private String phone = "";
    private String name = "";
    private final List<JSONObject> messages = new ArrayList<>();
    private BaseAdapter adapter;
    private ListView list;
    private EditText draft;
    private Button send;
    private TextView state;

    static Intent intent(Context c, @Nullable String contactId, String phone, String name) {
        return new Intent(c, ThreadActivity.class)
                .putExtra(EXTRA_CONTACT, contactId)
                .putExtra(EXTRA_PHONE, phone)
                .putExtra(EXTRA_NAME, name);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        contactId = getIntent().getStringExtra(EXTRA_CONTACT);
        String p = getIntent().getStringExtra(EXTRA_PHONE);
        phone = p == null ? "" : p;
        String n = getIntent().getStringExtra(EXTRA_NAME);
        name = n == null || n.isEmpty() ? PhoneNumbers.display(phone) : n;
        setContentView(build());
        load();
        markRead();
    }

    private View build() {
        LinearLayout root = Ui.column(this, 12);

        LinearLayout header = Ui.row(this);
        header.addView(Ui.button(this, "Back", "plain", v -> finish()));
        TextView title = Ui.text(this, name, 19, R.color.text, true);
        title.setPadding(Ui.dp(this, 12), 0, Ui.dp(this, 12), 0);
        title.setSingleLine(true);
        header.addView(title, Ui.weight(1f));
        header.addView(Ui.button(this, getString(R.string.call), "primary", v -> Calls.start(this, phone, name)));
        root.addView(header, Ui.matchWrap(this, 0));

        state = Ui.text(this, getString(R.string.loading), 15, R.color.muted, false);
        state.setPadding(0, Ui.dp(this, 8), 0, 0);
        root.addView(state, Ui.matchWrap(this, 0));

        adapter = new BaseAdapter() {
            @Override public int getCount() { return messages.size(); }
            @Override public Object getItem(int i) { return messages.get(i); }
            @Override public long getItemId(int i) { return i; }
            @Override public View getView(int i, View convertView, ViewGroup parent) { return bubble(messages.get(i)); }
        };
        list = new ListView(this);
        list.setAdapter(adapter);
        list.setDivider(null);
        list.setTranscriptMode(ListView.TRANSCRIPT_MODE_ALWAYS_SCROLL);
        list.setStackFromBottom(true);
        root.addView(list, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout compose = Ui.row(this);
        draft = Ui.input(this, R.string.message_hint, InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        draft.setMaxLines(4);
        compose.addView(draft, Ui.weight(1f));
        send = Ui.button(this, getString(R.string.send), "primary", v -> sendDraft());
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        sp.leftMargin = Ui.dp(this, 8);
        compose.addView(send, sp);
        root.addView(compose, Ui.matchWrap(this, 8));
        return root;
    }

    private View bubble(JSONObject m) {
        boolean mine = JsonRows.str(m, "direction").toLowerCase().startsWith("out");
        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setGravity(mine ? Gravity.END : Gravity.START);
        wrap.setPadding(0, Ui.dp(this, 4), 0, Ui.dp(this, 4));
        String body = JsonRows.str(m, "body");
        if (body.isEmpty() && !JsonRows.str(m, "media_url").isEmpty()) body = "(attachment)";
        TextView text = Ui.text(this, body, 17, mine ? R.color.on_accent : R.color.text, false);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Ui.color(this, mine ? R.color.accent : R.color.surface2));
        bg.setCornerRadius(Ui.dp(this, 16));
        text.setBackground(bg);
        text.setPadding(Ui.dp(this, 14), Ui.dp(this, 10), Ui.dp(this, 14), Ui.dp(this, 10));
        text.setMaxWidth(Math.round(getResources().getDisplayMetrics().widthPixels * 0.78f));
        text.setTextIsSelectable(true);
        wrap.addView(text);
        String meta = TimeText.shortText(JsonRows.str(m, "created_at"));
        String delivery = JsonRows.str(m, "delivery_status").toLowerCase();
        if (mine && (delivery.equals("failed") || delivery.equals("undelivered"))) meta = meta + " · Not delivered";
        TextView when = Ui.text(this, meta, 13, meta.contains("Not delivered") ? R.color.danger_text : R.color.muted, false);
        wrap.addView(when);
        return wrap;
    }

    private String threadQuery() {
        if (contactId != null && !contactId.isEmpty()) return "contactId=" + Uri.encode(contactId);
        return "phone=" + Uri.encode(phone);
    }

    private void load() {
        if ((contactId == null || contactId.isEmpty()) && phone.isEmpty()) { state.setText("This conversation has no phone number."); return; }
        Api.get(this, "/communications/sms/thread?" + threadQuery(), (res, err) -> {
            if (err != null) { state.setText(err); return; }
            JSONArray items = JsonRows.list(res, "messages", "data", "items");
            messages.clear();
            for (int i = 0; i < items.length(); i++) {
                JSONObject m = items.optJSONObject(i);
                if (m != null) messages.add(m);
            }
            adapter.notifyDataSetChanged();
            state.setText(messages.isEmpty() ? getString(R.string.nothing_here) : "");
            state.setVisibility(messages.isEmpty() ? View.VISIBLE : View.GONE);
            if (!messages.isEmpty()) list.setSelection(messages.size() - 1);
        });
    }

    private void markRead() {
        JSONObject body = new JSONObject();
        try {
            if (contactId != null && !contactId.isEmpty()) body.put("contactId", contactId);
            else if (!phone.isEmpty()) body.put("phone", phone);
            else return;
        } catch (JSONException e) {
            return;
        }
        Api.post(this, "/communications/messages/mark-read", body, (res, err) -> { /* best effort */ });
    }

    private void sendDraft() {
        String text = draft.getText().toString().trim();
        if (text.isEmpty()) return;
        String to = PhoneNumbers.e164(phone);
        if (to == null) { Ui.toast(this, "This conversation has no phone number to reply to."); return; }
        JSONObject body = new JSONObject();
        try {
            body.put("to", to);
            body.put("body", text);
            if (contactId != null && !contactId.isEmpty()) body.put("contactId", contactId);
        } catch (JSONException ignored) { }
        send.setEnabled(false);
        Api.post(this, "/communications/sms", body, (res, err) -> {
            send.setEnabled(true);
            if (err != null) { Ui.toast(this, "Couldn't send that message. " + err); return; }
            draft.setText("");
            load();
        });
    }
}

package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - the dialler's main screen: Keypad, Recents, Contacts, Messages and Voicemail tabs, with the
// account, the line and whether this phone is ready to take calls at the top. Opened by the launcher, by the staff
// portal's call link (<scheme>://call?phone=...), by a tapped phone number (tel:) and by a tapped staff alert.

import android.Manifest;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.boreal.dialer.voice.VoiceCallManager;

public class MainActivity extends AppCompatActivity implements VoiceCallManager.Listener {

    public static final String EXTRA_TAB = "tab";
    public static final String EXTRA_CALL = "call";
    private static final int FIRST_RUN_PERMISSIONS = 52;

    private final Map<String, Panel> panels = new LinkedHashMap<>();
    private final Map<String, Button> tabs = new LinkedHashMap<>();
    private FrameLayout content;
    private TextView readiness;
    private Button lineButton;
    private KeypadPanel keypad;
    private VoicemailPanel voicemail;
    @Nullable private String current;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!Session.signedIn(this)) {
            startActivity(new Intent(this, LoginActivity.class));
            finish();
            return;
        }
        Api.setSignedOutListener(this::signedOutByServer);
        setContentView(build());
        askFirstRunPermissions();
        if (!handle(getIntent())) show(AlertRules.TAB_KEYPAD);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        handle(intent);
    }

    @Override
    protected void onStart() {
        super.onStart();
        if (!Session.signedIn(this)) return;
        VoiceCallManager.get(this).addListener(this);
        VoiceSetup.startRefresh(this);
        renderReadiness();
    }

    @Override
    protected void onStop() {
        VoiceCallManager.get(this).removeListener(this);
        VoiceSetup.stopRefresh();
        if (voicemail != null) voicemail.stop();
        super.onStop();
    }

    // ------------------------------------------------------------------ layout

    private View build() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);

        LinearLayout header = Ui.row(this);
        header.setPadding(Ui.dp(this, 16), Ui.dp(this, 12), Ui.dp(this, 12), Ui.dp(this, 4));
        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        String company = Session.company(this);
        titles.addView(Ui.text(this, company == null || company.isEmpty() ? getString(R.string.app_name) : company, 20, R.color.text, true));
        readiness = Ui.text(this, "", 14, R.color.muted, false);
        readiness.setOnClickListener(v -> retryRegistration());
        titles.addView(readiness);
        header.addView(titles, Ui.weight(1f));
        if (AppConfig.lines().length > 1) {
            lineButton = Ui.button(this, AppConfig.lineName(Session.line(this)), "plain", v -> chooseLine());
            lineButton.setContentDescription("Calling line");
            header.addView(lineButton);
        }
        Button signOut = Ui.button(this, getString(R.string.sign_out), "plain", v -> confirmSignOut());
        LinearLayout.LayoutParams so = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        so.leftMargin = Ui.dp(this, 8);
        header.addView(signOut, so);
        root.addView(header);

        content = new FrameLayout(this);
        root.addView(content, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        keypad = new KeypadPanel(this);
        voicemail = new VoicemailPanel(this);
        panels.put(AlertRules.TAB_KEYPAD, keypad);
        panels.put(AlertRules.TAB_RECENTS, new RecentsPanel(this));
        panels.put(AlertRules.TAB_CONTACTS, new ContactsPanel(this));
        panels.put(AlertRules.TAB_MESSAGES, new MessagesPanel(this));
        panels.put(AlertRules.TAB_VOICEMAIL, voicemail);

        LinearLayout bar = Ui.row(this);
        bar.setBackgroundColor(Ui.color(this, R.color.surface));
        bar.setPadding(Ui.dp(this, 4), Ui.dp(this, 4), Ui.dp(this, 4), Ui.dp(this, 4));
        addTab(bar, AlertRules.TAB_KEYPAD, R.string.tab_keypad);
        addTab(bar, AlertRules.TAB_RECENTS, R.string.tab_recents);
        addTab(bar, AlertRules.TAB_CONTACTS, R.string.tab_contacts);
        addTab(bar, AlertRules.TAB_MESSAGES, R.string.tab_messages);
        addTab(bar, AlertRules.TAB_VOICEMAIL, R.string.tab_voicemail);
        root.addView(bar);
        return root;
    }

    private void addTab(LinearLayout bar, String key, int label) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14);
        b.setBackgroundColor(Ui.color(this, R.color.surface));
        b.setMinHeight(Ui.dp(this, 52));
        b.setPadding(0, 0, 0, 0);
        b.setOnClickListener(v -> show(key));
        bar.addView(b, Ui.weight(1f));
        tabs.put(key, b);
    }

    private void show(String key) {
        Panel panel = panels.get(key);
        if (panel == null) return;
        if (!key.equals(AlertRules.TAB_VOICEMAIL) && voicemail != null) voicemail.stop();
        current = key;
        content.removeAllViews();
        content.addView(panel.view(), new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));
        for (Map.Entry<String, Button> e : tabs.entrySet()) {
            boolean on = e.getKey().equals(key);
            e.getValue().setTextColor(Ui.color(this, on ? R.color.accent_text : R.color.muted));
            e.getValue().setTypeface(on ? android.graphics.Typeface.DEFAULT_BOLD : android.graphics.Typeface.DEFAULT);
            e.getValue().setSelected(on);
        }
        panel.onShow();
    }

    // ------------------------------------------------------------------ intents

    /** True when the intent chose a tab. */
    private boolean handle(@Nullable Intent intent) {
        if (intent == null) return false;
        String call = intent.getStringExtra(EXTRA_CALL);
        String tab = intent.getStringExtra(EXTRA_TAB);
        Uri data = intent.getData();
        setIntent(new Intent(this, MainActivity.class)); // handled once, not again on rotation
        if (call != null) {
            NotificationManagerCompat.from(this).cancelAll();
            show(AlertRules.TAB_KEYPAD);
            keypad.setNumber(call);
            Calls.start(this, call, null);
            return true;
        }
        if (data != null) {
            DeepLinks.Target target = DeepLinks.parse(data.toString(), AppConfig.deepLinkScheme());
            if (target == null) {
                Ui.toast(this, "That call link isn't valid.");
                return false;
            }
            show(AlertRules.TAB_KEYPAD);
            if (target.phone != null) dialTarget(target.phone, null, target.start);
            else if (target.contactId != null) dialContact(target.contactId, target.start);
            return true;
        }
        if (tab != null && panels.containsKey(tab)) {
            show(tab);
            return true;
        }
        return false;
    }

    private void dialTarget(String phone, @Nullable String name, boolean start) {
        keypad.setNumber(phone);
        if (start) Calls.start(this, phone, name);
    }

    private void dialContact(String contactId, boolean start) {
        Api.get(this, "/crm/contacts/" + Uri.encode(contactId), (res, err) -> {
            JSONObject c = res == null ? null : res.optJSONObject("data");
            if (c == null) c = res;
            String phone = JsonRows.str(c, "phone");
            if (err != null || PhoneNumbers.e164(phone) == null) {
                Ui.toast(this, err != null ? err : "That contact has no phone number.");
                return;
            }
            dialTarget(phone, JsonRows.contactName(c), start);
        });
    }

    // ------------------------------------------------------------------ calls and permissions

    private void askFirstRunPermissions() {
        List<String> ask = new ArrayList<>();
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ask.add(Manifest.permission.RECORD_AUDIO);
        }
        if (Build.VERSION.SDK_INT >= 33
                && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            ask.add(Manifest.permission.POST_NOTIFICATIONS);
        }
        if (!ask.isEmpty()) ActivityCompat.requestPermissions(this, ask.toArray(new String[0]), FIRST_RUN_PERMISSIONS);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode == Calls.MIC_REQUEST) {
            Calls.onMicResult(this, results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED);
        }
    }

    @Override
    public void onVoiceEvent(@NonNull String event, @NonNull JSONObject data) {
        runOnUiThread(() -> {
            if ("registrationChanged".equals(event)) renderReadiness();
            if ("callEnded".equals(event) && AlertRules.TAB_RECENTS.equals(current)) {
                Panel p = panels.get(AlertRules.TAB_RECENTS);
                if (p != null) p.onShow();
            }
        });
    }

    private void renderReadiness() {
        if (readiness == null) return;
        VoiceCallManager m = VoiceCallManager.get(this);
        String line = AppConfig.lines().length > 1 ? AppConfig.lineName(Session.line(this)) + " · " : "";
        if (m.isRegistered()) {
            readiness.setText(line + getString(R.string.calls_ready));
            readiness.setTextColor(Ui.color(this, R.color.accent_text));
        } else {
            readiness.setText(line + getString(R.string.calls_not_ready) + ". Tap to try again.");
            readiness.setTextColor(Ui.color(this, R.color.muted));
        }
    }

    private void retryRegistration() {
        readiness.setText(R.string.loading);
        VoiceSetup.register(this, (ok, err) -> runOnUiThread(() -> {
            renderReadiness();
            if (!ok) Ui.toast(this, err != null && err.contains("firebase")
                    ? "This build can't ring while closed (no Firebase file). Calls you place still work."
                    : (err != null ? err : getString(R.string.calls_not_ready)));
        }));
    }

    private void chooseLine() {
        String[] ids = AppConfig.lines();
        String[] names = new String[ids.length];
        for (int i = 0; i < ids.length; i++) names[i] = AppConfig.lineName(ids[i]);
        new AlertDialog.Builder(this)
                .setTitle("Call from which line?")
                .setItems(names, (d, which) -> {
                    Session.setLine(this, ids[which]);
                    if (lineButton != null) lineButton.setText(names[which]);
                    retryRegistration();
                    if (current != null && !AlertRules.TAB_KEYPAD.equals(current)) show(current);
                })
                .show();
    }

    // ------------------------------------------------------------------ sign-out

    private void confirmSignOut() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.sign_out)
                .setMessage("This phone will stop ringing for your calls until you sign in again.")
                .setPositiveButton(R.string.sign_out, (d, w) -> signOut())
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }

    private void signOut() {
        if (VoiceCallManager.get(this).current() != null) { Ui.toast(this, "Finish the call first."); return; }
        PushRegistrar.remove(this, () -> {
            VoiceCallManager.get(this).unregister();
            finishSignOut();
        });
    }

    /** The server refused the session (expired or revoked): stop ringing and go back to sign-in. */
    private void signedOutByServer() {
        if (!Session.signedIn(this)) return;
        VoiceCallManager.get(this).unregister();
        finishSignOut();
    }

    private void finishSignOut() {
        Session.clear(this);
        NotificationManagerCompat.from(this).cancelAll();
        startActivity(new Intent(this, LoginActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
        finish();
    }
}

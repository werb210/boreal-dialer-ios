package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - sign-in with a text code, the same as the iPhone dialler:
//   POST /api/auth/otp/start  { phone }
//   POST /api/auth/otp/verify { phone, code, userType: "staff" } -> { status: "ok", data: { token } }
// Only staff roles may sign in (a client sign-in would never ring).
//
// Builds without a fixed server first find the staff member's company server (the iPhone dialler's KS_STAFF_DIRECTORY_v1):
//   POST {KS-Ops}/api/staff-directory/lookup { identifier } -> { matches: [{ name, server_url }] }
//   GET  {KS-Ops}/api/directory/{code}                      -> { company_name, server_url } (the company-code fallback)

import android.app.AlertDialog;
import android.content.Intent;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;


public class LoginActivity extends AppCompatActivity {

    private EditText phoneInput;
    private EditText codeInput;
    private EditText companyInput;
    private TextView status;
    private Button sendButton;
    private Button verifyButton;
    private LinearLayout phoneStep;
    private LinearLayout codeStep;
    private LinearLayout companyStep;
    @Nullable private String phone;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(build());
    }

    private View build() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout root = Ui.column(this, 24);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        scroll.addView(root);

        TextView app = Ui.text(this, getString(R.string.app_name), 28, R.color.text, true);
        app.setGravity(Gravity.CENTER);
        app.setPadding(0, Ui.dp(this, 32), 0, Ui.dp(this, 4));
        root.addView(app, Ui.matchWrap(this, 0));
        TextView title = Ui.text(this, getString(R.string.sign_in_title), 20, R.color.muted, false);
        title.setGravity(Gravity.CENTER);
        root.addView(title, Ui.matchWrap(this, 0));

        phoneStep = Ui.column(this, 0);
        TextView help = Ui.text(this, getString(R.string.sign_in_phone_help), 16, R.color.muted, false);
        phoneStep.addView(help, Ui.matchWrap(this, 24));
        phoneInput = Ui.input(this, R.string.sign_in_phone_hint, InputType.TYPE_CLASS_PHONE);
        phoneInput.setContentDescription(getString(R.string.sign_in_phone_hint));
        phoneStep.addView(phoneInput, Ui.matchWrap(this, 12));
        sendButton = Ui.button(this, getString(R.string.sign_in_send_code), "primary", v -> sendCode());
        phoneStep.addView(sendButton, Ui.matchWrap(this, 16));
        root.addView(phoneStep, Ui.matchWrap(this, 0));

        companyStep = Ui.column(this, 0);
        companyStep.setVisibility(View.GONE);
        companyInput = Ui.input(this, R.string.sign_in_company_code_hint, InputType.TYPE_CLASS_TEXT);
        companyStep.addView(companyInput, Ui.matchWrap(this, 16));
        root.addView(companyStep, Ui.matchWrap(this, 0));

        if (AppConfig.findsServerAtSignIn()) {
            TextView useCode = Ui.text(this, getString(R.string.sign_in_company_code), 16, R.color.accent_text, false);
            useCode.setGravity(Gravity.CENTER);
            useCode.setPadding(0, Ui.dp(this, 16), 0, Ui.dp(this, 16));
            useCode.setOnClickListener(v -> companyStep.setVisibility(View.VISIBLE));
            phoneStep.addView(useCode, Ui.matchWrap(this, 4));
        }

        codeStep = Ui.column(this, 0);
        codeStep.setVisibility(View.GONE);
        codeInput = Ui.input(this, R.string.sign_in_code_hint, InputType.TYPE_CLASS_NUMBER);
        codeInput.setContentDescription(getString(R.string.sign_in_code_hint));
        codeStep.addView(codeInput, Ui.matchWrap(this, 24));
        verifyButton = Ui.button(this, getString(R.string.sign_in_verify), "primary", v -> verify());
        codeStep.addView(verifyButton, Ui.matchWrap(this, 16));
        TextView change = Ui.text(this, getString(R.string.sign_in_change_number), 16, R.color.accent_text, false);
        change.setGravity(Gravity.CENTER);
        change.setPadding(0, Ui.dp(this, 16), 0, Ui.dp(this, 16));
        change.setOnClickListener(v -> showPhoneStep());
        codeStep.addView(change, Ui.matchWrap(this, 4));
        root.addView(codeStep, Ui.matchWrap(this, 0));

        status = Ui.text(this, "", 16, R.color.danger_text, false);
        status.setGravity(Gravity.CENTER);
        root.addView(status, Ui.matchWrap(this, 16));
        return scroll;
    }

    private void busy(boolean on) {
        sendButton.setEnabled(!on);
        verifyButton.setEnabled(!on);
        if (on) { status.setTextColor(Ui.color(this, R.color.muted)); status.setText(R.string.loading); }
    }

    private void fail(String message) {
        busy(false);
        status.setTextColor(Ui.color(this, R.color.danger_text));
        status.setText(message);
    }

    private void showPhoneStep() {
        codeStep.setVisibility(View.GONE);
        phoneStep.setVisibility(View.VISIBLE);
        status.setText("");
    }

    private void sendCode() {
        String number = PhoneNumbers.e164(phoneInput.getText().toString());
        if (number == null) { fail("Enter your mobile number with the area code."); return; }
        phone = number;
        busy(true);
        if (!AppConfig.findsServerAtSignIn()) { startOtp(); return; }
        String code = companyInput.getText().toString().trim();
        if (companyStep.getVisibility() == View.VISIBLE && !code.isEmpty()) lookupCompanyCode(code);
        else lookupByPhone(number);
    }

    private void lookupByPhone(String number) {
        JSONObject body = new JSONObject();
        try { body.put("identifier", number); } catch (JSONException ignored) { }
        Api.openRequest("POST", AppConfig.opsUrl() + "/api/staff-directory/lookup", body, (res, err) -> {
            if (err != null || res == null) { fail(err != null ? err : "The company directory isn't responding. Try again."); return; }
            JSONArray matches = res.optJSONArray("matches");
            if (matches == null || matches.length() == 0) {
                companyStep.setVisibility(View.VISIBLE);
                fail("We couldn't find a company for that mobile number. Check it, or enter your company code.");
                return;
            }
            if (matches.length() == 1) { useServer(matches.optJSONObject(0)); return; }
            String[] names = new String[matches.length()];
            for (int i = 0; i < matches.length(); i++) {
                JSONObject m = matches.optJSONObject(i);
                names[i] = m == null ? "" : m.optString("name", m.optString("server_url", ""));
            }
            busy(false);
            new AlertDialog.Builder(this)
                    .setTitle(R.string.sign_in_pick_company)
                    .setItems(names, (d, which) -> { busy(true); useServer(matches.optJSONObject(which)); })
                    .show();
        });
    }

    private void lookupCompanyCode(String code) {
        if (!code.matches("^[A-Za-z0-9-]{3,32}$")) { fail("Company codes are 3 to 32 letters, numbers or dashes."); return; }
        String url = AppConfig.opsUrl() + "/api/directory/" + code.toLowerCase(java.util.Locale.ROOT); // checked above: letters, digits, dashes
        Api.openRequest("GET", url, null, (res, err) -> {
            if (err != null || res == null) { fail("We couldn't find that company code. Check it with your administrator."); return; }
            JSONObject match = new JSONObject();
            try {
                match.put("name", res.optString("company_name", ""));
                match.put("server_url", res.optString("server_url", ""));
            } catch (JSONException ignored) { }
            useServer(match);
        });
    }

    private void useServer(@Nullable JSONObject match) {
        String server = match == null ? "" : match.optString("server_url", "").trim();
        if (!server.startsWith("https://")) { fail("That company's server address isn't set up. Ask your administrator."); return; }
        Session.chooseServer(this, AppConfig.apiBaseFromServer(server), match.optString("name", ""));
        startOtp();
    }

    private void startOtp() {
        String base = Session.apiBase(this);
        if (base == null || phone == null) { fail("Choose your company first."); return; }
        JSONObject body = new JSONObject();
        try { body.put("phone", phone); } catch (JSONException ignored) { }
        Api.postOpen(base + "/auth/otp/start", body, (res, err) -> {
            if (err != null) { fail(err); return; }
            busy(false);
            status.setText("");
            phoneStep.setVisibility(View.GONE);
            companyStep.setVisibility(View.GONE);
            codeStep.setVisibility(View.VISIBLE);
            codeInput.requestFocus();
        });
    }

    private void verify() {
        String code = codeInput.getText().toString().trim();
        String base = Session.apiBase(this);
        if (!code.matches("^[0-9]{4,8}$")) { fail("Enter the code from the text message."); return; }
        if (base == null || phone == null) { showPhoneStep(); return; }
        busy(true);
        JSONObject body = new JSONObject();
        try {
            body.put("phone", phone);
            body.put("code", code);
            body.put("userType", "staff");
        } catch (JSONException ignored) { }
        Api.postOpen(base + "/auth/otp/verify", body, (res, err) -> {
            if (err != null || res == null) { fail(err != null ? err : "Sign-in failed. Try again."); return; }
            JSONObject data = res.optJSONObject("data");
            String token = data != null ? data.optString("token", "") : res.optString("token", "");
            if (token.isEmpty()) { fail("Sign-in failed. Try again."); return; }
            if (!Jwt.isCallingRole(Jwt.claim(token, "role"))) {
                fail(ApiErrors.message(403, "not_staff", null));
                return;
            }
            Session.saveToken(this, token);
            PushRegistrar.upload(this, true);
            VoiceSetup.register(this, null);
            startActivity(new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
            finish();
        });
    }
}

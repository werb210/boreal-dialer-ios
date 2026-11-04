package com.boreal.dialer.voice;

// BOREAL_ANDROID_DIALER_v1 - the native call screen. Opens over the lock screen when a call rings (the notification's
// full-screen intent) and stays the call's screen until it ends: Answer / Decline while ringing, then Mute, Speaker,
// Keypad and Hang up with a running timer. Works without the rest of the app open, so a call can be answered and handled
// from a locked phone. "Open the dialler" goes back to the app.

import android.Manifest;
import android.app.KeyguardManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONObject;

import java.util.Locale;

import com.boreal.dialer.MainActivity;
import com.boreal.dialer.R;

public class CallActivity extends AppCompatActivity implements VoiceCallManager.Listener {

    public static final String ACTION_SHOW = "com.boreal.dialer.voice.SHOW";
    public static final String ACTION_ANSWER = "com.boreal.dialer.voice.ANSWER";
    public static final String ACTION_CLOSE = "com.boreal.dialer.voice.CLOSE";

    // Fixed call colours, both with white text above 4.5:1 contrast (5.6:1 and 6.0:1).
    private static final int GREEN = 0xFF1E7D32;
    private static final int RED = 0xFFB3261E;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private VoiceCallManager manager;
    private TextView name;
    private TextView status;
    private LinearLayout ringingRow;
    private LinearLayout callRow;
    private GridLayout keypad;
    private TextView digits;
    private Button muteButton;
    private Button speakerButton;
    private int onBrand;

    private final BroadcastReceiver closer = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { finishSoon(); }
    };

    private final Runnable tick = new Runnable() {
        @Override public void run() {
            render();
            handler.postDelayed(this, 1000);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        } else {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
        }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        manager = VoiceCallManager.get(this);
        onBrand = ContextCompat.getColor(this, R.color.text);
        setContentView(buildLayout());
        ContextCompat.registerReceiver(this, closer, new IntentFilter(ACTION_CLOSE), ContextCompat.RECEIVER_NOT_EXPORTED);
        manager.addListener(this);
        handle(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handle(intent);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (manager.current() == null) { finish(); return; }
        handler.removeCallbacks(tick);
        handler.post(tick);
    }

    @Override
    protected void onPause() {
        super.onPause();
        handler.removeCallbacks(tick);
    }

    @Override
    protected void onDestroy() {
        manager.removeListener(this);
        try { unregisterReceiver(closer); } catch (IllegalArgumentException ignored) { }
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    private void handle(Intent intent) {
        if (intent != null && ACTION_ANSWER.equals(intent.getAction())) answer();
        render();
    }

    private void answer() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, new String[] { Manifest.permission.RECORD_AUDIO }, 41);
        }
        manager.answer(null);
    }

    @Override
    public void onVoiceEvent(@NonNull String event, @NonNull JSONObject data) {
        runOnUiThread(() -> {
            if ("callEnded".equals(event)) finishSoon();
            else render();
        });
    }

    private void finishSoon() {
        if (status != null) status.setText(R.string.call_ended);
        handler.postDelayed(this::finish, 900);
    }

    // ------------------------------------------------------------------ layout

    private int dp(int v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()));
    }

    private Button roundButton(String label, int fill, int text, View.OnClickListener click) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setTextColor(text);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(fill);
        bg.setCornerRadius(dp(32));
        b.setBackground(bg);
        b.setMinHeight(dp(64));
        b.setPadding(dp(16), dp(8), dp(16), dp(8));
        b.setOnClickListener(click);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        lp.setMargins(dp(8), dp(8), dp(8), dp(8));
        b.setLayoutParams(lp);
        return b;
    }

    private int translucent() {
        return (onBrand & 0x00FFFFFF) | 0x26000000; // on-brand colour at 15%
    }

    private View buildLayout() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setBackgroundColor(ContextCompat.getColor(this, R.color.bg));
        root.setPadding(dp(24), dp(56), dp(24), dp(32));

        TextView app = new TextView(this);
        app.setText(R.string.app_name);
        app.setTextColor(onBrand);
        app.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        app.setGravity(Gravity.CENTER);
        root.addView(app);

        name = new TextView(this);
        name.setTextColor(onBrand);
        name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 32);
        name.setTypeface(Typeface.DEFAULT_BOLD);
        name.setGravity(Gravity.CENTER);
        name.setPadding(0, dp(32), 0, dp(8));
        root.addView(name);

        status = new TextView(this);
        status.setTextColor(onBrand);
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        status.setGravity(Gravity.CENTER);
        root.addView(status);

        digits = new TextView(this);
        digits.setTextColor(onBrand);
        digits.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        digits.setGravity(Gravity.CENTER);
        digits.setPadding(0, dp(16), 0, 0);
        root.addView(digits);

        keypad = new GridLayout(this);
        keypad.setColumnCount(3);
        keypad.setVisibility(View.GONE);
        String[] keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" };
        for (String k : keys) {
            Button key = new Button(this);
            key.setText(k);
            key.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
            key.setTextColor(onBrand);
            GradientDrawable bg = new GradientDrawable();
            bg.setColor(translucent());
            bg.setCornerRadius(dp(36));
            key.setBackground(bg);
            GridLayout.LayoutParams lp = new GridLayout.LayoutParams();
            lp.width = dp(72);
            lp.height = dp(72);
            lp.setMargins(dp(8), dp(8), dp(8), dp(8));
            key.setLayoutParams(lp);
            key.setOnClickListener(v -> {
                manager.sendDigits(k);
                digits.append(k);
            });
            keypad.addView(key);
        }
        LinearLayout.LayoutParams kp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        kp.gravity = Gravity.CENTER_HORIZONTAL;
        kp.topMargin = dp(8);
        root.addView(keypad, kp);

        View spacer = new View(this);
        root.addView(spacer, new LinearLayout.LayoutParams(1, 0, 1f));

        callRow = new LinearLayout(this);
        callRow.setOrientation(LinearLayout.VERTICAL);
        LinearLayout tools = new LinearLayout(this);
        tools.setOrientation(LinearLayout.HORIZONTAL);
        muteButton = roundButton(getString(R.string.mute), translucent(), onBrand, v -> { manager.mute(!manager.isMuted()); render(); });
        speakerButton = roundButton(getString(R.string.speaker), translucent(), onBrand, v -> { manager.speaker(!manager.isSpeaker()); render(); });
        Button keypadButton = roundButton(getString(R.string.keypad), translucent(), onBrand,
                v -> keypad.setVisibility(keypad.getVisibility() == View.VISIBLE ? View.GONE : View.VISIBLE));
        tools.addView(muteButton);
        tools.addView(speakerButton);
        tools.addView(keypadButton);
        callRow.addView(tools);
        LinearLayout endRow = new LinearLayout(this);
        endRow.addView(roundButton(getString(R.string.hang_up), RED, 0xFFFFFFFF, v -> manager.hangup()));
        callRow.addView(endRow);
        root.addView(callRow);

        ringingRow = new LinearLayout(this);
        ringingRow.setOrientation(LinearLayout.HORIZONTAL);
        ringingRow.addView(roundButton(getString(R.string.decline), RED, 0xFFFFFFFF, v -> manager.reject(null)));
        ringingRow.addView(roundButton(getString(R.string.answer), GREEN, 0xFFFFFFFF, v -> answer()));
        root.addView(ringingRow);

        TextView open = new TextView(this);
        open.setText(R.string.open_app);
        open.setTextColor(onBrand);
        open.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        open.setGravity(Gravity.CENTER);
        open.setPadding(dp(16), dp(20), dp(16), dp(4));
        open.setPaintFlags(open.getPaintFlags() | android.graphics.Paint.UNDERLINE_TEXT_FLAG);
        open.setOnClickListener(v -> openApp());
        root.addView(open);
        return root;
    }

    private void openApp() {
        Intent i = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        KeyguardManager km = (KeyguardManager) getSystemService(KEYGUARD_SERVICE);
        if (km != null && km.isKeyguardLocked() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            km.requestDismissKeyguard(this, new KeyguardManager.KeyguardDismissCallback() {
                @Override public void onDismissSucceeded() { startActivity(i); }
            });
        } else {
            startActivity(i);
        }
    }

    private void render() {
        VoiceCallManager.CallSession s = manager.current();
        if (s == null || name == null) return;
        name.setText(s.label());
        boolean ringing = !s.outgoing && s.call == null;
        ringingRow.setVisibility(ringing ? View.VISIBLE : View.GONE);
        callRow.setVisibility(ringing ? View.GONE : View.VISIBLE);
        if (ringing) {
            status.setText(R.string.incoming_call);
        } else if ("connected".equals(s.phase) && s.connectedAt > 0) {
            long secs = (System.currentTimeMillis() - s.connectedAt) / 1000;
            status.setText(String.format(Locale.US, "%d:%02d", secs / 60, secs % 60));
        } else {
            status.setText(R.string.calling);
        }
        muteButton.setText(manager.isMuted() ? R.string.unmute : R.string.mute);
        speakerButton.setText(manager.isSpeaker() ? R.string.speaker_off : R.string.speaker);
    }
}

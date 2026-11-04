package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - voicemail (GET /api/crm/voicemails -> { data }). Tap to play (the audio comes from
// GET /api/crm/voicemails/:id/audio with the staff token), call back or text. Nothing plays during a call.

import android.app.Activity;
import android.app.AlertDialog;
import android.media.AudioAttributes;
import android.media.MediaPlayer;

import androidx.annotation.Nullable;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import com.boreal.dialer.voice.VoiceCallManager;

final class VoicemailPanel extends ListPanel {

    @Nullable private MediaPlayer player;

    VoicemailPanel(Activity activity) { super(activity, false); }

    @Override
    protected void load(int g) {
        Api.get(activity, "/crm/voicemails", (res, err) -> {
            if (err != null) { showError(g, err); return; }
            JSONArray items = JsonRows.list(res, "data", "items", "voicemails");
            List<RowAdapter.Row> rows = new ArrayList<>();
            for (int i = 0; i < items.length(); i++) {
                JSONObject v = items.optJSONObject(i);
                if (v == null) continue;
                String name = JsonRows.str(v, "contact_name");
                String phone = JsonRows.str(v, "contact_phone");
                String title = name.isEmpty() ? (phone.isEmpty() ? "Unknown caller" : PhoneNumbers.display(phone)) : name;
                String transcript = JsonRows.str(v, "transcript");
                String duration = TimeText.duration(JsonRows.num(v, "duration_seconds"));
                String subtitle = transcript.isEmpty() ? (duration.isEmpty() ? "Voicemail" : "Voicemail · " + duration) : transcript;
                rows.add(new RowAdapter.Row(title, subtitle, TimeText.shortText(JsonRows.str(v, "created_at")), false, false, v));
            }
            show(g, rows);
        });
    }

    @Override
    protected void onTap(RowAdapter.Row row) {
        JSONObject v = (JSONObject) row.item;
        String phone = JsonRows.str(v, "contact_phone");
        String contactId = JsonRows.str(v, "contact_id");
        boolean playing = player != null && player.isPlaying();
        List<String> options = new ArrayList<>();
        options.add(playing ? "Stop" : "Play");
        boolean hasPhone = PhoneNumbers.e164(phone) != null;
        if (hasPhone) { options.add(activity.getString(R.string.call_back)); options.add(activity.getString(R.string.text_message)); }
        new AlertDialog.Builder(activity)
                .setTitle(row.title)
                .setMessage(row.subtitle)
                .setItems(options.toArray(new String[0]), (d, which) -> {
                    if (which == 0) { if (playing) stop(); else play(JsonRows.str(v, "id")); }
                    else if (which == 1) Calls.start(activity, phone, row.title);
                    else activity.startActivity(ThreadActivity.intent(activity, contactId.isEmpty() ? null : contactId, phone, row.title));
                })
                .show();
    }

    private void play(String id) {
        if (!id.matches("^[A-Za-z0-9_-]{1,128}$")) return;
        if (VoiceCallManager.get(activity).current() != null) { Ui.toast(activity, "Voicemail can't play during a call."); return; }
        Ui.toast(activity, activity.getString(R.string.loading));
        Api.bytes(activity, "/crm/voicemails/" + id + "/audio", (bytes, err) -> {
            if (bytes == null || bytes.length == 0) { Ui.toast(activity, err != null ? err : "This voicemail has no recording."); return; }
            if (VoiceCallManager.get(activity).current() != null) { Ui.toast(activity, "Voicemail can't play during a call."); return; }
            File file = new File(activity.getCacheDir(), "voicemail.mp3");
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(bytes);
            } catch (IOException e) {
                Ui.toast(activity, "The voicemail couldn't be saved to play.");
                return;
            }
            stop();
            MediaPlayer p = new MediaPlayer();
            try {
                p.setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build());
                p.setDataSource(file.getAbsolutePath());
                p.setOnCompletionListener(mp -> stop());
                p.prepare();
                p.start();
                player = p;
            } catch (IOException | RuntimeException e) {
                p.release();
                Ui.toast(activity, "The voicemail couldn't be played.");
            }
        });
    }

    void stop() {
        if (player != null) {
            try { player.stop(); } catch (IllegalStateException ignored) { }
            player.release();
            player = null;
        }
    }
}

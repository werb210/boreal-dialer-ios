package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - a tab that shows a list from the server: optional search box, Refresh, the list, and a line
// that says when it is loading, empty or failed.

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import androidx.annotation.Nullable;

import java.util.List;

abstract class ListPanel implements Panel {

    protected final Activity activity;
    protected final RowAdapter adapter;
    private final LinearLayout root;
    private final TextView state;
    @Nullable protected EditText search;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable searchLater = this::reload;
    private int generation = 0;

    ListPanel(Activity activity, boolean withSearch) {
        this.activity = activity;
        this.adapter = new RowAdapter(activity);
        root = Ui.column(activity, 12);

        LinearLayout top = Ui.row(activity);
        if (withSearch) {
            search = Ui.input(activity, R.string.search_hint, InputType.TYPE_CLASS_TEXT);
            search.addTextChangedListener(new TextWatcher() {
                @Override public void beforeTextChanged(CharSequence s, int a, int b, int c) { }
                @Override public void onTextChanged(CharSequence s, int a, int b, int c) { }
                @Override public void afterTextChanged(Editable s) {
                    handler.removeCallbacks(searchLater);
                    handler.postDelayed(searchLater, 350);
                }
            });
            top.addView(search, Ui.weight(1f));
        } else {
            top.addView(new View(activity), Ui.weight(1f));
        }
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        rp.leftMargin = Ui.dp(activity, 8);
        top.addView(Ui.button(activity, activity.getString(R.string.refresh), "plain", v -> reload()), rp);
        root.addView(top, Ui.matchWrap(activity, 0));

        state = Ui.text(activity, "", 16, R.color.muted, false);
        state.setPadding(Ui.dp(activity, 4), Ui.dp(activity, 12), Ui.dp(activity, 4), Ui.dp(activity, 4));
        root.addView(state, Ui.matchWrap(activity, 0));

        ListView list = new ListView(activity);
        list.setAdapter(adapter);
        list.setDivider(new android.graphics.drawable.ColorDrawable(Ui.color(activity, R.color.line)));
        list.setDividerHeight(1);
        list.setOnItemClickListener((p, v, pos, id) -> onTap(adapter.getItem(pos)));
        list.setOnItemLongClickListener((p, v, pos, id) -> { onLongPress(adapter.getItem(pos)); return true; });
        root.addView(list, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));
    }

    protected String query() {
        return search == null ? "" : search.getText().toString().trim();
    }

    /** Loads the rows; call show() or showError() with the generation it was given. */
    protected abstract void load(int generation);

    protected abstract void onTap(RowAdapter.Row row);

    protected void onLongPress(RowAdapter.Row row) { onTap(row); }

    protected final void reload() {
        int g = ++generation;
        state.setText(R.string.loading);
        state.setVisibility(View.VISIBLE);
        load(g);
    }

    protected final void show(int g, List<RowAdapter.Row> rows) {
        if (g != generation) return; // an older search answered late
        adapter.set(rows);
        if (rows.isEmpty()) state.setText(R.string.nothing_here);
        else state.setVisibility(View.GONE);
    }

    protected final void showError(int g, String error) {
        if (g != generation) return;
        state.setText(error);
        state.setVisibility(View.VISIBLE);
    }

    /** Call or text someone (a contact, a recent call, a voicemail). */
    protected final void callOrText(String name, String phone, @Nullable String contactId) {
        if (PhoneNumbers.e164(phone) == null) { Ui.toast(activity, "There's no phone number for " + name + "."); return; }
        String[] options = { activity.getString(R.string.call), activity.getString(R.string.text_message) };
        new AlertDialog.Builder(activity)
                .setTitle(name + " · " + PhoneNumbers.display(phone))
                .setItems(options, (d, which) -> {
                    if (which == 0) Calls.start(activity, phone, name);
                    else activity.startActivity(ThreadActivity.intent(activity, contactId, phone, name));
                })
                .show();
    }

    @Override public View view() { return root; }

    @Override public void onShow() { reload(); }

}

package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - one list row style for Recents, Contacts, Messages and Voicemail: a title, a second line and
// a time on the right.

import android.content.Context;
import android.text.TextUtils;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;

import java.util.ArrayList;
import java.util.List;

public final class RowAdapter extends BaseAdapter {

    public static final class Row {
        public final String title;
        public final String subtitle;
        public final String meta;
        public final boolean alert; // red title: a missed call
        public final boolean unread;
        @Nullable public final Object item;

        public Row(String title, String subtitle, String meta, boolean alert, boolean unread, @Nullable Object item) {
            this.title = title;
            this.subtitle = subtitle;
            this.meta = meta;
            this.alert = alert;
            this.unread = unread;
            this.item = item;
        }
    }

    private final Context context;
    private final List<Row> rows = new ArrayList<>();

    public RowAdapter(Context context) { this.context = context; }

    public void set(List<Row> next) {
        rows.clear();
        rows.addAll(next);
        notifyDataSetChanged();
    }

    @Override public int getCount() { return rows.size(); }

    @Override public Row getItem(int position) { return rows.get(position); }

    @Override public long getItemId(int position) { return position; }

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
        Row r = rows.get(position);
        LinearLayout line = Ui.row(context);
        int pad = Ui.dp(context, 14);
        line.setPadding(pad, Ui.dp(context, 12), pad, Ui.dp(context, 12));
        line.setMinimumHeight(Ui.dp(context, 64));

        LinearLayout texts = new LinearLayout(context);
        texts.setOrientation(LinearLayout.VERTICAL);
        TextView title = Ui.text(context, r.title, 17, r.alert ? R.color.danger_text : R.color.text, r.unread);
        title.setSingleLine(true);
        title.setEllipsize(TextUtils.TruncateAt.END);
        texts.addView(title);
        if (!r.subtitle.isEmpty()) {
            TextView sub = Ui.text(context, r.subtitle, 15, R.color.muted, false);
            sub.setMaxLines(2);
            sub.setEllipsize(TextUtils.TruncateAt.END);
            texts.addView(sub);
        }
        line.addView(texts, Ui.weight(1f));
        if (!r.meta.isEmpty()) {
            TextView meta = Ui.text(context, r.meta, 14, R.color.muted, false);
            meta.setPadding(Ui.dp(context, 8), 0, 0, 0);
            line.addView(meta);
        }
        line.setContentDescription(r.title + ". " + r.subtitle + ". " + r.meta);
        return line;
    }
}

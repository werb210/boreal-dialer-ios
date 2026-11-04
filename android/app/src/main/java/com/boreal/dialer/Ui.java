package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - small view builders so every screen uses the same readable colours and sizes. Text sizes are
// in sp, so the phone's font-size setting applies.

import android.content.Context;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.core.content.ContextCompat;

public final class Ui {

    private Ui() { }

    public static int dp(Context c, int v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics()));
    }

    public static int color(Context c, int res) { return ContextCompat.getColor(c, res); }

    public static TextView text(Context c, CharSequence value, int sp, int colorRes, boolean bold) {
        TextView t = new TextView(c);
        t.setText(value);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color(c, colorRes));
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    private static GradientDrawable round(int fill, float radius) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(fill);
        g.setCornerRadius(radius);
        return g;
    }

    /** A filled button. kind: "primary" (green), "danger" (red) or "plain" (dark grey). */
    public static Button button(Context c, CharSequence label, String kind, View.OnClickListener click) {
        Button b = new Button(c);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        int fill;
        int text;
        if ("primary".equals(kind)) { fill = color(c, R.color.accent); text = color(c, R.color.on_accent); }
        else if ("danger".equals(kind)) { fill = color(c, R.color.danger); text = color(c, R.color.on_danger); }
        else { fill = color(c, R.color.surface2); text = color(c, R.color.text); }
        b.setTextColor(text);
        b.setBackground(round(fill, dp(c, 12)));
        b.setMinHeight(dp(c, 52));
        b.setPadding(dp(c, 16), dp(c, 8), dp(c, 16), dp(c, 8));
        b.setOnClickListener(click);
        return b;
    }

    public static EditText input(Context c, int hintRes, int inputType) {
        EditText e = new EditText(c);
        e.setHint(hintRes);
        e.setInputType(inputType);
        e.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        e.setTextColor(color(c, R.color.text));
        e.setHintTextColor(color(c, R.color.muted));
        e.setBackground(round(color(c, R.color.surface), dp(c, 12)));
        e.setPadding(dp(c, 14), dp(c, 12), dp(c, 14), dp(c, 12));
        e.setSingleLine(inputType != (InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE));
        return e;
    }

    public static LinearLayout column(Context c, int padDp) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.VERTICAL);
        int p = dp(c, padDp);
        l.setPadding(p, p, p, p);
        return l;
    }

    public static LinearLayout row(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.HORIZONTAL);
        l.setGravity(Gravity.CENTER_VERTICAL);
        return l;
    }

    public static LinearLayout.LayoutParams matchWrap(Context c, int topDp) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(c, topDp);
        return lp;
    }

    public static LinearLayout.LayoutParams weight(float w) {
        return new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, w);
    }

    public static void toast(Context c, CharSequence message) {
        Toast.makeText(c, message, Toast.LENGTH_LONG).show();
    }
}

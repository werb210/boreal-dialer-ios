package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - the dial pad: type or paste a number, then Call. Hold 0 for "+".

import android.app.Activity;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

final class KeypadPanel implements Panel {

    private final Activity activity;
    private final LinearLayout root;
    private final TextView number;
    private final StringBuilder digits = new StringBuilder();

    KeypadPanel(Activity activity) {
        this.activity = activity;
        root = Ui.column(activity, 16);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        number = Ui.text(activity, "", 34, R.color.text, false);
        number.setGravity(Gravity.CENTER);
        number.setSingleLine(true);
        number.setPadding(0, Ui.dp(activity, 16), 0, Ui.dp(activity, 16));
        number.setContentDescription("Number to call");
        root.addView(number, Ui.matchWrap(activity, 0));

        GridLayout grid = new GridLayout(activity);
        grid.setColumnCount(3);
        String[][] keys = {
                { "1", "" }, { "2", "ABC" }, { "3", "DEF" }, { "4", "GHI" }, { "5", "JKL" }, { "6", "MNO" },
                { "7", "PQRS" }, { "8", "TUV" }, { "9", "WXYZ" }, { "*", "" }, { "0", "+" }, { "#", "" },
        };
        for (String[] k : keys) grid.addView(key(k[0], k[1]));
        LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        gp.gravity = Gravity.CENTER_HORIZONTAL;
        root.addView(grid, gp);

        LinearLayout actions = Ui.row(activity);
        Button delete = Ui.button(activity, "Delete", "plain", v -> {
            if (digits.length() > 0) digits.deleteCharAt(digits.length() - 1);
            render();
        });
        delete.setOnLongClickListener(v -> { digits.setLength(0); render(); return true; });
        Button call = Ui.button(activity, activity.getString(R.string.call), "primary",
                v -> Calls.start(activity, digits.toString(), null));
        LinearLayout.LayoutParams dl = Ui.weight(1f);
        dl.rightMargin = Ui.dp(activity, 8);
        actions.addView(delete, dl);
        LinearLayout.LayoutParams cl = Ui.weight(2f);
        cl.leftMargin = Ui.dp(activity, 8);
        actions.addView(call, cl);
        root.addView(actions, Ui.matchWrap(activity, 16));
    }

    private View key(String digit, String letters) {
        Button b = new Button(activity);
        b.setAllCaps(false);
        b.setText(letters.isEmpty() ? digit : digit + "\n" + letters);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        b.setTextColor(Ui.color(activity, R.color.text));
        b.setContentDescription(digit);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Ui.color(activity, R.color.surface2));
        bg.setCornerRadius(Ui.dp(activity, 40));
        b.setBackground(bg);
        GridLayout.LayoutParams lp = new GridLayout.LayoutParams();
        lp.width = Ui.dp(activity, 80);
        lp.height = Ui.dp(activity, 80);
        lp.setMargins(Ui.dp(activity, 10), Ui.dp(activity, 8), Ui.dp(activity, 10), Ui.dp(activity, 8));
        b.setLayoutParams(lp);
        b.setOnClickListener(v -> { if (digits.length() < 20) digits.append(digit); render(); });
        if ("0".equals(digit)) b.setOnLongClickListener(v -> { if (digits.length() < 20) digits.append('+'); render(); return true; });
        return b;
    }

    void setNumber(String value) {
        digits.setLength(0);
        for (char ch : value.toCharArray()) if (PhoneNumbers.isDialKey(ch)) digits.append(ch);
        render();
    }

    private void render() { number.setText(PhoneNumbers.display(digits.toString())); }

    @Override public View view() { return root; }

    @Override public void onShow() { render(); }
}

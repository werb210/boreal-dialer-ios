package com.boreal.dialer;

import android.view.View;

/** BOREAL_ANDROID_DIALER_v1 - one tab of the main screen. */
interface Panel {
    View view();

    /** The tab was opened: load or refresh what it shows. */
    void onShow();
}

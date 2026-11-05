package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - server times (ISO 8601) as short local text: "2:05 PM" today, "Mon 2:05 PM" this week,
// "Oct 3" otherwise.

import androidx.annotation.Nullable;

import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Locale;

public final class TimeText {

    private TimeText() { }

    @Nullable
    public static ZonedDateTime parse(@Nullable String iso, ZoneId zone) {
        if (iso == null || iso.trim().isEmpty()) return null;
        String s = iso.trim();
        try {
            return OffsetDateTime.parse(s).atZoneSameInstant(zone);
        } catch (DateTimeParseException e) {
            try {
                return Instant.parse(s).atZone(zone);
            } catch (DateTimeParseException again) {
                try {
                    return OffsetDateTime.parse(s.replace(' ', 'T')).atZoneSameInstant(zone);
                } catch (DateTimeParseException last) {
                    return null;
                }
            }
        }
    }

    public static String shortText(@Nullable String iso, ZoneId zone, LocalDate today) {
        ZonedDateTime t = parse(iso, zone);
        if (t == null) return "";
        LocalDate d = t.toLocalDate();
        if (d.equals(today)) return t.format(DateTimeFormatter.ofPattern("h:mm a", Locale.US));
        if (!d.isBefore(today.minusDays(6)) && !d.isAfter(today)) return t.format(DateTimeFormatter.ofPattern("EEE h:mm a", Locale.US));
        return t.format(DateTimeFormatter.ofPattern("MMM d", Locale.US));
    }

    public static String shortText(@Nullable String iso) {
        ZoneId zone = ZoneId.systemDefault();
        return shortText(iso, zone, LocalDate.now(zone));
    }

    /** 75 -> "1:15". */
    public static String duration(int seconds) {
        if (seconds <= 0) return "";
        return String.format(Locale.US, "%d:%02d", seconds / 60, seconds % 60);
    }
}

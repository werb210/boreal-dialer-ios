package com.boreal.dialer;

// BOREAL_ANDROID_DIALER_v1 - the dialler's rules that do not need a phone: numbers, call links, sign-in roles, alert
// routing, readable errors and times. Run with: ./gradlew testDebugUnitTest. No real client data.

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Base64;

public class DialerRulesTest {

    private static final String SCHEME = "borealdialer";

    @Test
    public void phoneNumbersBecomeE164() {
        assertEquals("+14035550199", PhoneNumbers.e164("(403) 555-0199"));
        assertEquals("+14035550199", PhoneNumbers.e164("1 403 555 0199"));
        assertEquals("+14035550199", PhoneNumbers.e164("+1 403-555-0199"));
        assertEquals("+442071838750", PhoneNumbers.e164("+44 20 7183 8750"));
        assertNull(PhoneNumbers.e164("555-0199"));
        assertNull(PhoneNumbers.e164("someone@example.com"));
        assertNull(PhoneNumbers.e164("403 555 01ab"));
        assertNull(PhoneNumbers.e164(""));
        assertNull(PhoneNumbers.e164(null));
        assertEquals("(403) 555-0199", PhoneNumbers.display("+14035550199"));
        assertEquals("(403) 555-0199", PhoneNumbers.display("client:+14035550199"));
        assertEquals("403", PhoneNumbers.display("403"));
    }

    @Test
    public void callLinksFromThePortal() {
        DeepLinks.Target t = DeepLinks.parse("borealdialer://call?phone=%2B14035550199", SCHEME);
        assertNotNull(t);
        assertEquals("+14035550199", t.phone);
        assertFalse(t.start);

        t = DeepLinks.parse("borealdialer://call?phone=%2B14035550199&start=true", SCHEME);
        assertNotNull(t);
        assertTrue(t.start);

        t = DeepLinks.parse("borealdialer://call?contactId=c0c0c0c0-0000-4000-8000-000000000002", SCHEME);
        assertNotNull(t);
        assertEquals("c0c0c0c0-0000-4000-8000-000000000002", t.contactId);
        assertNull(t.phone);

        t = DeepLinks.parse("tel:+1-403-555-0199", SCHEME);
        assertNotNull(t);
        assertEquals("+14035550199", t.phone);
    }

    @Test
    public void badCallLinksAreRefused() {
        assertNull(DeepLinks.parse("borealdialer://call?phone=4035550199", SCHEME)); // not E.164
        assertNull(DeepLinks.parse("borealdialer://call?phone=%2B14035550199&phone=%2B14035550100", SCHEME)); // duplicate
        assertNull(DeepLinks.parse("borealdialer://call?phone=%2B14035550199&contactId=abc", SCHEME)); // both
        assertNull(DeepLinks.parse("borealdialer://call?phone=%2B14035550199&url=https://example.com", SCHEME)); // unknown key
        assertNull(DeepLinks.parse("borealdialer://text?phone=%2B14035550199", SCHEME)); // unknown route
        assertNull(DeepLinks.parse("otherapp://call?phone=%2B14035550199", SCHEME)); // another scheme
        assertNull(DeepLinks.parse("borealdialer://call?start=yes&phone=%2B14035550199", SCHEME));
        StringBuilder longId = new StringBuilder();
        for (int i = 0; i < 129; i++) longId.append('a');
        assertNull(DeepLinks.parse("borealdialer://call?contactId=" + longId, SCHEME));
        assertNull(DeepLinks.parse("borealdialer://call?contactId=../etc", SCHEME));
        assertNull(DeepLinks.parse("borealdialer://call", SCHEME));
    }

    private static String token(String payloadJson) {
        Base64.Encoder enc = Base64.getUrlEncoder().withoutPadding();
        return enc.encodeToString("{\"alg\":\"HS256\"}".getBytes(StandardCharsets.UTF_8)) + "."
                + enc.encodeToString(payloadJson.getBytes(StandardCharsets.UTF_8)) + ".sig";
    }

    @Test
    public void onlyStaffRolesSignIn() {
        assertEquals("Staff", Jwt.claim(token("{\"sub\":\"u1\",\"role\":\"Staff\"}"), "role"));
        assertTrue(Jwt.isCallingRole("Staff"));
        assertTrue(Jwt.isCallingRole(" admin "));
        assertTrue(Jwt.isCallingRole("Broker"));
        assertTrue(Jwt.isCallingRole("Marketing"));
        assertFalse(Jwt.isCallingRole("client"));
        assertFalse(Jwt.isCallingRole("Lender"));
        assertFalse(Jwt.isCallingRole(null));
        assertNull(Jwt.claim("not-a-token", "role"));
        assertNull(Jwt.claim(token("{\"sub\":\"u1\"}"), "role"));
    }

    @Test
    public void alertsOpenTheRightTab() {
        assertEquals(AlertRules.TAB_VOICEMAIL, AlertRules.tabFor("VOICEMAIL"));
        assertEquals(AlertRules.TAB_MESSAGES, AlertRules.tabFor("SMS"));
        assertEquals(AlertRules.TAB_MESSAGES, AlertRules.tabFor("CLIENT_MESSAGE"));
        assertEquals(AlertRules.TAB_MESSAGES, AlertRules.tabFor("HANDOFF"));
        assertEquals(AlertRules.TAB_RECENTS, AlertRules.tabFor("MISSED_CALL"));
        assertEquals(AlertRules.TAB_RECENTS, AlertRules.tabFor(null));
        assertTrue(AlertRules.offersCallBack("MISSED_CALL", "+14035550199"));
        assertTrue(AlertRules.offersCallBack("VOICEMAIL", "+14035550199"));
        assertFalse(AlertRules.offersCallBack("SMS", "+14035550199"));
        assertFalse(AlertRules.offersCallBack("MISSED_CALL", "4035550199"));
        assertFalse(AlertRules.offersCallBack("MISSED_CALL", "javascript:alert(1)"));
        assertTrue(AlertRules.drawsHere("MISSED_CALL"));
        assertTrue(AlertRules.drawsHere("SMS"));
        assertFalse(AlertRules.drawsHere("TASK")); // the staff portal app shows tasks
        assertEquals("calls", AlertRules.channelKind("VOICEMAIL"));
        assertEquals("tasks", AlertRules.channelKind("TASK"));
        assertEquals("messages", AlertRules.channelKind("SMS"));
    }

    @Test
    public void errorsAreReadable() {
        assertEquals("That phone number isn't valid.", ApiErrors.message(400, "invalid_to", null));
        assertEquals("Your session has expired. Sign in again.", ApiErrors.message(401, null, null));
        assertTrue(ApiErrors.message(0, null, null).startsWith("No connection"));
        assertEquals("Ask the office to add you first.", ApiErrors.message(403, "x", "Ask the office to add you first."));
        assertEquals("The server had a problem (500). Try again in a moment.",
                ApiErrors.message(500, null, "relation \"calls\" does not exist"));
        assertEquals("The server refused that (418).", ApiErrors.message(418, null, null));
    }

    @Test
    public void timesAreShortAndLocal() {
        // A fixed offset (Mountain Standard Time), so the result never depends on the machine's time-zone database.
        ZoneId edmonton = ZoneId.of("-07:00");
        LocalDate today = LocalDate.of(2026, 11, 4);
        assertEquals("2:05 PM", TimeText.shortText("2026-11-04T21:05:00Z", edmonton, today));
        assertEquals("Mon 9:00 AM", TimeText.shortText("2026-11-02T16:00:00.000Z", edmonton, today));
        assertEquals("Oct 3", TimeText.shortText("2026-10-03T16:00:00+00:00", edmonton, today));
        assertEquals("", TimeText.shortText("not a date", edmonton, today));
        assertEquals("1:15", TimeText.duration(75));
        assertEquals("", TimeText.duration(0));
    }

    @Test
    public void serverAddresses() {
        assertEquals("https://acme.example.com/api", AppConfig.apiBaseFromServer("https://acme.example.com/"));
        assertEquals("https://acme.example.com/api", AppConfig.apiBaseFromServer("https://acme.example.com/api"));
    }
}

import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { formatDialed, DIAL_PREFIX } from "../DialPad";

const root = path.resolve(__dirname, "../../../..");

describe("BOREAL_DIALER_KEYPAD_UI_v147", () => {
  it("groups a NANP number as it is typed", () => {
    expect(formatDialed("")).toBe("");
    expect(formatDialed("58")).toBe("58");
    expect(formatDialed("587")).toBe("587");
    expect(formatDialed("587555")).toBe("(587) 555");
    expect(formatDialed("5875551234")).toBe("(587) 555-1234");
  });

  it("leaves anything that is not a plain 10-digit number alone", () => {
    expect(formatDialed("*67")).toBe("*67");
    expect(formatDialed("011447700900123")).toBe("011447700900123");
  });

  it("ignores separators the user may have pasted", () => {
    expect(formatDialed("(587) 555-1234")).toBe("(587) 555-1234");
  });

  it("shows the country prefix as a chip rather than part of the number", () => {
    expect(DIAL_PREFIX).toBe("+1");
    const src = fs.readFileSync(path.join(root, "src/telephony/components/DialPad.tsx"), "utf8");
    expect(src).toContain("bd-kp-prefix");
    expect(src).toContain("Enter number");
  });

  it("drops the Delete and Clear text buttons for a backspace glyph", () => {
    const src = fs.readFileSync(path.join(root, "src/telephony/components/DialPad.tsx"), "utf8");
    expect(src).toContain("bd-backspace");
    expect(src).not.toMatch(/>Delete</);
    expect(src).not.toMatch(/>Clear</);
  });

  it("makes the call button inert with nothing dialled", () => {
    const src = fs.readFileSync(path.join(root, "src/telephony/components/DialPad.tsx"), "utf8");
    expect(src).toContain("is-idle");
    expect(src).toContain("disabled={!hasNumber}");
  });

  it("sizes the keypad off the viewport instead of a fixed inset column", () => {
    const css = fs.readFileSync(path.join(root, "src/styles.css"), "utf8");
    expect(css).toContain("width:min(23vw,86px)");
    expect(css).not.toContain("padding:16px 44px 6px");
  });
});

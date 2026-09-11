import { describe, it, expect } from "vitest";
import { expandShortcut, insertAt, bodyOf, filterTemplates, type Snippet, type Template } from "../snippets";

const SNIPS: Snippet[] = [
  { id: "1", name: "Personal net worth", shortcut: "pnw", body_text: "Please complete the personal net worth statement." },
  { id: "2", name: "Bank statements", shortcut: "bank", body_text: "Could you send the last 6 months of bank statements?" },
  { id: "3", name: "Html one", shortcut: "html", body_html: "<p>Hello<br/>there</p>" },
  { id: "4", name: "Empty", shortcut: "empty", body_text: "" },
];

describe("BOREAL_DIALER_SNIPPETS_v156", () => {
  it("expands a shortcut at the caret", () => {
    const out = expandShortcut("#pnw", 4, SNIPS);
    expect(out?.value).toBe("Please complete the personal net worth statement.");
    expect(out?.caret).toBe(out?.value.length);
  });

  it("expands mid-sentence and keeps what follows", () => {
    const out = expandShortcut("Hi there #bank", 14, SNIPS);
    expect(out?.value).toBe("Hi there Could you send the last 6 months of bank statements?");
  });

  it("preserves text after the caret", () => {
    const out = expandShortcut("#pnw rest", 4, SNIPS);
    expect(out?.value.endsWith(" rest")).toBe(true);
  });

  it("leaves a mid-word hash alone", () => {
    expect(expandShortcut("ref#pnw", 7, SNIPS)).toBeNull();
  });

  it("ignores an unknown shortcut", () => {
    expect(expandShortcut("#nope", 5, SNIPS)).toBeNull();
  });

  it("ignores a shortcut with an empty body", () => {
    expect(expandShortcut("#empty", 6, SNIPS)).toBeNull();
  });

  it("matches a shortcut case-insensitively", () => {
    expect(expandShortcut("#PNW", 4, SNIPS)?.value).toContain("personal net worth");
  });

  it("strips markup so HTML never lands in an SMS", () => {
    expect(bodyOf(SNIPS[2]!)).toBe("Hello\nthere");
    const out = expandShortcut("#html", 5, SNIPS);
    expect(out?.value).not.toContain("<");
  });

  it("inserts a template at the caret without replacing what was typed", () => {
    const out = insertAt("Hi  — Todd", 3, "please send docs");
    expect(out.value).toBe("Hi please send docs — Todd");
    expect(out.caret).toBe(3 + "please send docs".length);
  });

  it("clamps an out-of-range caret", () => {
    expect(insertAt("abc", 99, "X").value).toBe("abcX");
    expect(insertAt("abc", -5, "X").value).toBe("Xabc");
  });

  it("offers only active, non-snippet templates for the channel", () => {
    const items: Template[] = [
      { id: "a", name: "Active sms", channel: "sms" },
      { id: "b", name: "Inactive", channel: "sms", is_active: false },
      { id: "c", name: "A snippet", channel: "sms", is_snippet: true },
      { id: "d", name: "Email one", channel: "email" },
    ];
    expect(filterTemplates(items, "sms").map((i) => i.id)).toEqual(["a"]);
  });

  it("treats a template with no channel as email, matching the portal", () => {
    const items: Template[] = [{ id: "a", name: "No channel" }];
    expect(filterTemplates(items, "sms")).toEqual([]);
    expect(filterTemplates(items, "email").map((i) => i.id)).toEqual(["a"]);
  });
});

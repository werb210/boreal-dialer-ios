// BOREAL_DIALER_SNIPPETS_v156
// Snippets and templates in the dialer, so a staff member with only their
// phone can answer a client properly instead of thumbing out boilerplate.
//
// Deliberately the same contract the portal uses (BF-portal useSnippets /
// ComposerPulldowns): GET /api/templates for templates, the same endpoint with
// ?snippets=1 for snippets, the same "#shortcut" expansion. Same wording on
// both surfaces means staff learn it once.
import { apiGet } from "./apiClient";

export type Snippet = {
  id: string;
  name: string;
  channel?: string | null;
  shortcut?: string | null;
  body_text?: string | null;
  body_html?: string | null;
  subject?: string | null;
};

export type Template = Snippet & { is_active?: boolean | null; is_snippet?: boolean };

function unwrap<T>(payload: unknown): T[] {
  if (Array.isArray(payload)) return payload as T[];
  const items = (payload as { items?: unknown })?.items;
  if (Array.isArray(items)) return items as T[];
  const data = (payload as { data?: unknown })?.data;
  return Array.isArray(data) ? (data as T[]) : [];
}

/** Stored bodies may be HTML; markup expanded into an SMS box is worse than useless. */
export function bodyOf(entry: Snippet): string {
  if (entry.body_text) return entry.body_text;
  if (!entry.body_html) return "";
  return entry.body_html.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "").trim();
}

export async function fetchSnippets(channel = "sms"): Promise<Snippet[]> {
  try {
    const payload = await apiGet<unknown>(
      `/api/templates?snippets=1&channel=${encodeURIComponent(channel)}`,
    );
    return unwrap<Snippet>(payload);
  } catch {
    // A convenience, not a dependency: the composer still works without them.
    return [];
  }
}

/** Active, non-snippet templates for this channel - matching the portal's filter. */
export function filterTemplates(items: Template[], channel = "sms"): Template[] {
  return items.filter(
    (item) =>
      item.is_active !== false &&
      item.is_snippet !== true &&
      (!channel || (item.channel ?? "email") === channel),
  );
}

export async function fetchTemplates(channel = "sms"): Promise<Template[]> {
  try {
    return filterTemplates(unwrap<Template>(await apiGet<unknown>("/api/templates")), channel);
  } catch {
    return [];
  }
}

/**
 * Expands "#shortcut" into its body when the user types space, tab or enter.
 * Returns the new value and caret position, or null when the token before the
 * caret is not a shortcut - in which case the keystroke is left alone.
 *
 * A '#' mid-word is not a trigger: "ref#123" must stay as typed.
 */
export function expandShortcut(
  value: string,
  caret: number,
  snippets: Snippet[],
): { value: string; caret: number } | null {
  const before = value.slice(0, caret);
  const match = before.match(/(^|\s)#([a-z0-9_-]{1,40})$/i);
  if (!match || !match[2]) return null;

  const token = match[2].toLowerCase();
  const hit = snippets.find((s) => String(s.shortcut ?? "").toLowerCase() === token);
  if (!hit) return null;

  const body = bodyOf(hit);
  if (!body) return null;

  const hashAt = before.length - token.length - 1;
  return { value: value.slice(0, hashAt) + body + value.slice(caret), caret: hashAt + body.length };
}

/** Inserts a template at the caret rather than replacing what was typed. */
export function insertAt(value: string, caret: number, text: string): { value: string; caret: number } {
  const at = Math.max(0, Math.min(caret, value.length));
  return { value: value.slice(0, at) + text + value.slice(at), caret: at + text.length };
}

// BOREAL_DIALER_SNIPPETS_v156
import { useEffect, useState } from "react";
import {
  fetchSnippets,
  fetchTemplates,
  bodyOf,
  type Snippet,
  type Template,
} from "../lib/snippets";

type Props = {
  channel?: string;
  onInsert: (text: string) => void;
};

/**
 * The two dropdowns from the portal's composer, sized for a phone. Hides itself
 * entirely when there is nothing to offer, rather than showing empty pickers.
 */
export default function ComposerTools({ channel = "sms", onInsert }: Props) {
  const [snippets, setSnippets] = useState<Snippet[]>([]);
  const [templates, setTemplates] = useState<Template[]>([]);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const [s, t] = await Promise.all([fetchSnippets(channel), fetchTemplates(channel)]);
      if (!alive) return;
      setSnippets(s);
      setTemplates(t);
    })();
    return () => { alive = false; };
  }, [channel]);

  if (snippets.length === 0 && templates.length === 0) return null;

  return (
    <div className="bd-composer-tools">
      {templates.length > 0 ? (
        <select
          className="bd-tool-select"
          value=""
          onChange={(event) => {
            const hit = templates.find((item) => item.id === event.target.value);
            if (hit) onInsert(bodyOf(hit));
            event.target.value = "";
          }}
          aria-label="Insert template"
        >
          <option value="">Template…</option>
          {templates.map((item) => (
            <option key={item.id} value={item.id}>{item.name}</option>
          ))}
        </select>
      ) : null}

      {snippets.length > 0 ? (
        <select
          className="bd-tool-select"
          value=""
          onChange={(event) => {
            const hit = snippets.find((item) => item.id === event.target.value);
            if (hit) onInsert(bodyOf(hit));
            event.target.value = "";
          }}
          aria-label="Insert snippet"
        >
          <option value="">Snippet…</option>
          {snippets.map((item) => (
            <option key={item.id} value={item.id}>
              {item.shortcut ? `#${item.shortcut} — ${item.name}` : item.name}
            </option>
          ))}
        </select>
      ) : null}
    </div>
  );
}

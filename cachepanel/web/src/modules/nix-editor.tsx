import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, HighlightStyle, indentOnInput, syntaxHighlighting } from "@codemirror/language";
import { EditorState } from "@codemirror/state";
import { drawSelection, EditorView, highlightActiveLine, highlightActiveLineGutter, keymap, lineNumbers } from "@codemirror/view";
import { tags } from "@lezer/highlight";
import { nix } from "@replit/codemirror-lang-nix";
import { useEffect, useEffectEvent, useRef } from "react";

const highlight = HighlightStyle.define([
  { tag: [tags.keyword, tags.operatorKeyword], color: "var(--chart-5)" },
  { tag: [tags.string, tags.special(tags.string)], color: "var(--chart-3)" },
  { tag: [tags.number, tags.bool, tags.null], color: "var(--chart-2)" },
  { tag: [tags.comment, tags.lineComment, tags.blockComment], color: "var(--muted-foreground)", fontStyle: "italic" },
  { tag: [tags.propertyName, tags.attributeName], color: "var(--chart-1)" },
  { tag: [tags.variableName, tags.definition(tags.variableName)], color: "var(--foreground)" },
  { tag: [tags.url, tags.link], color: "var(--chart-4)" },
]);

const theme = EditorView.theme({
  "&": { backgroundColor: "var(--card)", color: "var(--foreground)", fontSize: "0.8rem", height: "100%" },
  ".cm-content": { fontFamily: "var(--font-mono)", caretColor: "var(--primary)", padding: "0.75rem 0" },
  ".cm-scroller": { fontFamily: "var(--font-mono)", lineHeight: "1.6" },
  ".cm-gutters": { backgroundColor: "var(--muted)", color: "var(--muted-foreground)", border: "none" },
  ".cm-activeLine": { backgroundColor: "color-mix(in oklch, var(--primary) 6%, transparent)" },
  ".cm-activeLineGutter": { backgroundColor: "color-mix(in oklch, var(--primary) 12%, transparent)" },
  "&.cm-focused": { outline: "none" },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
    backgroundColor: "color-mix(in oklch, var(--primary) 25%, transparent) !important",
  },
});

type NixEditorProps = { value: string; onChange?: (value: string) => void; readOnly?: boolean };

export function NixEditor({ value, onChange, readOnly = false }: NixEditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const initial = useRef({ value, readOnly });
  const changed = useEffectEvent((text: string) => onChange?.(text));

  useEffect(() => {
    const editor = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: initial.current.value,
        extensions: [
          lineNumbers(),
          highlightActiveLine(),
          highlightActiveLineGutter(),
          drawSelection(),
          history(),
          indentOnInput(),
          bracketMatching(),
          nix(),
          syntaxHighlighting(highlight),
          theme,
          keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
          EditorState.readOnly.of(initial.current.readOnly),
          EditorView.updateListener.of((update) => update.docChanged && changed(update.state.doc.toString())),
        ],
      }),
    });
    view.current = editor;
    return () => editor.destroy();
  }, []);

  // Restored revisions replace the text.
  useEffect(() => {
    const editor = view.current;
    if (!editor || editor.state.doc.toString() === value) return;
    editor.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: value } });
  }, [value]);

  return <div ref={host} className="h-full min-h-80 overflow-hidden rounded-lg border" />;
}

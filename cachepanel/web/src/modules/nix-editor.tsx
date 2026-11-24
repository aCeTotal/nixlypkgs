import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, foldGutter, foldKeymap, HighlightStyle, indentOnInput, syntaxHighlighting } from "@codemirror/language";
import { lintGutter, setDiagnostics } from "@codemirror/lint";
import { highlightSelectionMatches, searchKeymap } from "@codemirror/search";
import { EditorSelection, EditorState, type Extension } from "@codemirror/state";
import { drawSelection, EditorView, highlightActiveLine, highlightActiveLineGutter, keymap, lineNumbers } from "@codemirror/view";
import { tags } from "@lezer/highlight";
import { useEffect, useEffectEvent, useImperativeHandle, useRef, type Ref } from "react";
import { nix } from "./nix/language";
import type { SyntaxProblem } from "./queries";

const highlight = HighlightStyle.define([
  { tag: [tags.keyword, tags.controlKeyword], color: "var(--chart-5)" },
  { tag: [tags.string, tags.special(tags.string)], color: "var(--chart-3)" },
  { tag: [tags.number, tags.bool, tags.null], color: "var(--chart-2)" },
  { tag: [tags.lineComment, tags.blockComment], color: "var(--muted-foreground)", fontStyle: "italic" },
  { tag: tags.propertyName, color: "var(--chart-1)" },
  { tag: [tags.url, tags.literal], color: "var(--chart-4)" },
  { tag: [tags.brace, tags.squareBracket, tags.paren], color: "var(--muted-foreground)" },
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
  ".cm-selectionMatch": { backgroundColor: "color-mix(in oklch, var(--chart-3) 20%, transparent)" },
  ".cm-searchMatch": { backgroundColor: "color-mix(in oklch, var(--warning) 35%, transparent)", borderRadius: "2px" },
  ".cm-searchMatch-selected": { backgroundColor: "color-mix(in oklch, var(--warning) 70%, transparent)" },
  ".cm-foldGutter .cm-gutterElement": { cursor: "pointer", padding: "0 0.25rem" },
  ".cm-foldPlaceholder": { backgroundColor: "var(--muted)", border: "1px solid var(--border)", color: "var(--muted-foreground)" },
  ".cm-panels": { backgroundColor: "var(--popover)", color: "var(--popover-foreground)", borderColor: "var(--border)" },
  ".cm-panel.cm-search": { padding: "0.5rem 0.75rem", fontFamily: "var(--font-sans)", fontSize: "0.8rem" },
  ".cm-panel.cm-search input, .cm-panel.cm-search button": {
    borderRadius: "0.375rem",
    border: "1px solid var(--border)",
    backgroundColor: "var(--background)",
    color: "var(--foreground)",
    backgroundImage: "none",
  },
  ".cm-tooltip": { backgroundColor: "var(--popover)", color: "var(--popover-foreground)", border: "1px solid var(--border)" },
  ".cm-lintRange-error": { textDecorationColor: "var(--destructive)" },
});

export type NixEditorHandle = { jumpTo: (pos: number) => void };

type NixEditorProps = {
  value: string;
  onChange?: (value: string) => void;
  onCursor?: (pos: number) => void;
  onSave?: () => void;
  problem?: SyntaxProblem;
  readOnly?: boolean;
  // Nix unless another is given.
  language?: Extension;
  ref?: Ref<NixEditorHandle>;
};

export function NixEditor({ value, onChange, onCursor, onSave, problem, readOnly = false, language, ref }: NixEditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const initial = useRef({ value, readOnly, language });
  const changed = useEffectEvent((text: string) => onChange?.(text));
  const moved = useEffectEvent((pos: number) => onCursor?.(pos));
  const saved = useEffectEvent(() => onSave?.());

  useEffect(() => {
    const editor = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: initial.current.value,
        extensions: [
          lineNumbers(),
          foldGutter(),
          lintGutter(),
          highlightActiveLine(),
          highlightActiveLineGutter(),
          highlightSelectionMatches(),
          drawSelection(),
          history(),
          indentOnInput(),
          bracketMatching(),
          initial.current.language ?? nix(),
          syntaxHighlighting(highlight),
          theme,
          keymap.of([
            {
              key: "Mod-s",
              preventDefault: true,
              run: () => {
                saved();
                return true;
              },
            },
            ...defaultKeymap,
            ...historyKeymap,
            ...searchKeymap,
            ...foldKeymap,
            indentWithTab,
          ]),
          EditorState.readOnly.of(initial.current.readOnly),
          EditorView.updateListener.of((update) => {
            if (update.docChanged) changed(update.state.doc.toString());
            if (update.selectionSet) moved(update.state.selection.main.head);
          }),
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

  useEffect(() => {
    const editor = view.current;
    if (!editor) return;
    const { doc } = editor.state;
    const line = problem?.line && problem.line <= doc.lines ? doc.line(problem.line) : null;
    const from = line ? Math.min(line.from + Math.max((problem?.column ?? 1) - 1, 0), line.to) : 0;
    const diagnostics = problem?.error && line ? [{ from, to: Math.max(from, line.to), severity: "error" as const, message: problem.error }] : [];
    editor.dispatch(setDiagnostics(editor.state, diagnostics));
  }, [problem]);

  useImperativeHandle(ref, () => ({
    jumpTo(pos) {
      const editor = view.current;
      if (!editor) return;
      editor.dispatch({
        selection: EditorSelection.cursor(pos),
        effects: EditorView.scrollIntoView(pos, { y: "start", yMargin: 48 }),
      });
      editor.focus();
    },
  }), []);

  return <div ref={host} className="h-full min-h-80 overflow-hidden rounded-lg border" />;
}

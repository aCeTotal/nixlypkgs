import { autocompletion, closeBrackets, closeBracketsKeymap, completeAnyWord, completionKeymap } from "@codemirror/autocomplete";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, foldGutter, foldKeymap, indentOnInput, syntaxHighlighting } from "@codemirror/language";
import { lintGutter, setDiagnostics } from "@codemirror/lint";
import { unifiedMergeView } from "@codemirror/merge";
import { highlightSelectionMatches, searchKeymap } from "@codemirror/search";
import { Compartment, EditorSelection, EditorState } from "@codemirror/state";
import {
  crosshairCursor,
  drawSelection,
  dropCursor,
  EditorView,
  highlightActiveLine,
  highlightActiveLineGutter,
  highlightSpecialChars,
  keymap,
  lineNumbers,
  rectangularSelection,
} from "@codemirror/view";
import { useQuery } from "@tanstack/react-query";
import { useEffect, useEffectEvent, useImperativeHandle, useMemo, useRef, type Ref } from "react";
import { toast } from "sonner";
import { highlight } from "./highlight";
import { isNix, loadLanguage } from "./languages";
import { nixCompletion } from "./nix-completion";
import { prepare, type PreparedIndex } from "./nix-index";
import { formatSource, nixIndexQuery, type SyntaxProblem } from "./queries";
import { theme } from "./theme";

export type CodeEditorHandle = { jumpTo: (pos: number) => void; format: () => void };

type CodeEditorProps = {
  path: string;
  value: string;
  onChange?: (value: string) => void;
  onCursor?: (pos: number) => void;
  onSave?: () => void;
  problem?: SyntaxProblem;
  readOnly?: boolean;
  // Shows what changed against it.
  original?: string;
  ref?: Ref<CodeEditorHandle>;
};

export function CodeEditor({ path, value, onChange, onCursor, onSave, problem, readOnly = false, original, ref }: CodeEditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const initial = useRef({ path, value, readOnly });
  const language = useRef(new Compartment());
  const review = useRef(new Compartment());
  const nix = isNix(path);
  const { data } = useQuery({ ...nixIndexQuery, enabled: nix });
  const prepared = useMemo(() => (data ? prepare(data) : undefined), [data]);
  const index = useRef<PreparedIndex | undefined>(undefined);
  useEffect(() => {
    index.current = prepared;
  }, [prepared]);
  const changed = useEffectEvent((text: string) => onChange?.(text));
  const moved = useEffectEvent((pos: number) => onCursor?.(pos));
  const saved = useEffectEvent(() => onSave?.());

  const format = useEffectEvent(async () => {
    const editor = view.current;
    if (!editor || !isNix(initial.current.path) || initial.current.readOnly) return;
    const result = await formatSource(editor.state.doc.toString());
    if (result.error) {
      toast.error(`Cannot format: ${result.error}`);
      return;
    }
    const cursor = Math.min(editor.state.selection.main.head, result.source.length);
    editor.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: result.source }, selection: { anchor: cursor } });
  });

  useEffect(() => {
    const { path: file, value: text, readOnly: locked } = initial.current;
    const words = EditorState.languageData.of(() => [{ autocomplete: completeAnyWord }]);
    const nixWords = EditorState.languageData.of(() => [{ autocomplete: nixCompletion(() => index.current) }]);
    const editor = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: text,
        extensions: [
          lineNumbers(),
          foldGutter(),
          lintGutter(),
          highlightActiveLine(),
          highlightActiveLineGutter(),
          highlightSpecialChars(),
          highlightSelectionMatches(),
          drawSelection(),
          dropCursor(),
          rectangularSelection(),
          crosshairCursor(),
          EditorState.allowMultipleSelections.of(true),
          history(),
          indentOnInput(),
          bracketMatching(),
          closeBrackets(),
          autocompletion({ activateOnTyping: true, icons: false }),
          isNix(file) ? nixWords : words,
          language.current.of([]),
          review.current.of([]),
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
            {
              key: "Shift-Alt-f",
              preventDefault: true,
              run: () => {
                void format();
                return true;
              },
            },
            ...closeBracketsKeymap,
            ...completionKeymap,
            ...defaultKeymap,
            ...historyKeymap,
            ...searchKeymap,
            ...foldKeymap,
            indentWithTab,
          ]),
          EditorState.readOnly.of(locked),
          EditorView.updateListener.of((update) => {
            if (update.docChanged) changed(update.state.doc.toString());
            if (update.selectionSet) moved(update.state.selection.main.head);
          }),
        ],
      }),
    });
    view.current = editor;
    let alive = true;
    void loadLanguage(file).then((support) => {
      if (alive) editor.dispatch({ effects: language.current.reconfigure(support) });
    });
    return () => {
      alive = false;
      editor.destroy();
    };
  }, []);

  // Restores and formatting replace text.
  useEffect(() => {
    const editor = view.current;
    if (!editor || editor.state.doc.toString() === value) return;
    editor.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: value } });
  }, [value]);

  useEffect(() => {
    view.current?.dispatch({
      effects: review.current.reconfigure(original === undefined ? [] : unifiedMergeView({ original, mergeControls: false, gutter: true })),
    });
  }, [original]);

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
    format: () => void format(),
  }), []);

  return <div ref={host} className="h-full min-h-80 overflow-hidden rounded-lg border" />;
}

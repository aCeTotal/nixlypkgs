import { useMutation, useQuery } from "@tanstack/react-query";
import { Eye, FileQuestion, GitCommitVertical, History, Sparkles, Trash2, TriangleAlert, type LucideIcon } from "lucide-react";
import { useRef, useState, type Ref } from "react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { CodeEditor, type CodeEditorHandle } from "@/editor/code-editor";
import { isNix } from "@/editor/languages";
import { useSyntaxCheck } from "@/editor/use-syntax-check";

import { Button } from "@/ui/button";
import { Skeleton } from "@/ui/skeleton";
import { CommitButton } from "./commit-button";
import { CommitDialog } from "./commit-dialog";
import { commitChanges, fileQuery, treeQuery, type FileChange } from "./queries";


type FileEditorProps = {
  path: string;
  create: boolean;
  onCommitted: (path: string) => void;
  onHistory: () => void;
};

export function FileEditor({ path, create, onCommitted, onHistory }: FileEditorProps) {
  const file = useQuery({ ...fileQuery(path), enabled: !create });
  const root = useQuery(treeQuery(""));
  const latest = create ? "" : file.data?.text;
  const head = create ? root.data?.head : file.data?.head;
  if (file.isError) {
    return <Notice icon={FileQuestion} text="This file is not on main." />;
  }
  if (file.data?.binary) {
    return <Notice icon={FileQuestion} text="Binary or larger than 1 MiB; change it with git." />;
  }
  if (latest === undefined || head === undefined) {
    return <Skeleton className="h-[70vh]" />;
  }
  return <Editing key={path} path={path} create={create} latest={latest} head={head} onCommitted={onCommitted} onHistory={onHistory} />;
}

type EditingProps = FileEditorProps & { latest: string; head: string };

function Editing({ path, create, latest, head, onCommitted, onHistory }: EditingProps) {
  const [start, setStart] = useState(latest);
  const [draft, setDraft] = useState(latest);
  const [committing, setCommitting] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const editor = useRef<CodeEditorHandle>(null);
  const dirty = create || draft !== start;
  // Follow main until the first keystroke.
  if (!dirty && latest !== start) {
    setStart(latest);
    setDraft(latest);
  }
  const conflict = !create && dirty && latest !== start;
  const save = useMutation({
    mutationFn: ({ message, changes }: { message: string; changes: FileChange[] }) => commitChanges({ base: head, message, changes }),
    onSuccess: ({ sha }, { changes }) => {
      toast.success(`Committed ${shortSha(sha)}; testing builds it next`);
      setStart(changes[0].content ?? "");
      setCommitting(false);
      onCommitted(changes[0].content === null ? "" : path);
    },
  });
  return (
    <div className="flex h-full flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <p className="min-w-0 flex-1 truncate font-mono text-sm">
          {path}
          {dirty && <span className="ml-2 text-xs text-warning-foreground">{create ? "new file" : "edited"}</span>}
        </p>
        {isNix(path) && (
          <Button size="sm" variant="outline" onClick={() => editor.current?.format()} title="Format with nixfmt (Shift+Alt+F)">
            <Sparkles />
            Format
          </Button>
        )}
        <Button size="sm" variant={reviewing ? "secondary" : "outline"} onClick={() => setReviewing(!reviewing)} disabled={!dirty}>
          <Eye />
          Changes
        </Button>
        {!create && (
          <Button size="sm" variant="outline" onClick={onHistory}>
            <History />
            History
          </Button>
        )}
        {!create && (
          <CommitButton
            icon={Trash2}
            variant="destructive"
            destructive
            title={`Delete ${path}`}
            label="Delete"
            suggestion={`Delete ${path}`}
            pending={save.isPending}
            onCommit={(message) => save.mutate({ message, changes: [{ path, content: null }] })}
          />
        )}
        <Button size="sm" onClick={() => setCommitting(true)} disabled={!dirty || save.isPending}>
          <GitCommitVertical />
          Commit
        </Button>
      </div>
      {conflict && (
        <div className="flex flex-wrap items-center gap-3 rounded-lg border border-warning/40 bg-warning-soft px-3 py-2 text-sm">
          <TriangleAlert className="size-4 shrink-0 text-warning-foreground" />
          <span className="flex-1">Someone changed this file on main while you edited.</span>
          <Button size="sm" variant="outline" onClick={() => setDraft(latest)}>
            Take theirs
          </Button>
          <Button size="sm" variant="outline" onClick={() => setStart(latest)}>
            Keep mine
          </Button>
        </div>
      )}
      <div className="min-h-0 flex-1">
        <SourceEditor
          path={path}
          value={draft}
          original={reviewing && dirty ? start : undefined}
          onChange={setDraft}
          onSave={() => setCommitting(true)}
          ref={editor}
        />
      </div>
      <CommitDialog
        open={committing}
        title={create ? `Add ${path}` : `Commit ${path}`}
        label="Commit"
        suggestion={`${create ? "Add" : "Update"} ${path}`}
        pending={save.isPending}
        onOpenChange={setCommitting}
        changes={{ path, original: start, current: draft }}
        onCommit={(message) => save.mutate({ message, changes: [{ path, content: draft }] })}
      />
    </div>
  );
}

type SourceProps = {
  path: string;
  value: string;
  original: string | undefined;
  onChange: (value: string) => void;
  onSave: () => void;
  ref: Ref<CodeEditorHandle>;
};

function SourceEditor(props: SourceProps) {
  return isNix(props.path) ? <NixSource {...props} /> : <CodeEditor {...props} />;
}

// Nix syntax errors while typing.
function NixSource(props: SourceProps) {
  const { problem } = useSyntaxCheck(props.value);
  return <CodeEditor {...props} problem={problem} />;
}

function Notice({ icon: Icon, text }: { icon: LucideIcon; text: string }) {
  return (
    <div className="grid h-full min-h-80 place-items-center rounded-lg border border-dashed text-sm text-muted-foreground">
      <span className="flex items-center gap-2">
        <Icon className="size-4" />
        {text}
      </span>
    </div>
  );
}

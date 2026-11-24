import { useMutation, useQuery } from "@tanstack/react-query";
import { FileQuestion, GitCommitVertical, History, Trash2, TriangleAlert, type LucideIcon } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { NixEditor } from "@/modules/nix-editor";
import { useSyntaxCheck } from "@/modules/use-syntax-check";
import { ConfirmButton } from "@/shell/confirm-button";
import { Button } from "@/ui/button";
import { Skeleton } from "@/ui/skeleton";
import { CommitDialog } from "./commit-dialog";
import { commitChanges, fileQuery, treeQuery, type FileChange } from "./queries";

// Plain text for anything but Nix.
const plain = [] as const;

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
  const isNix = path.endsWith(".nix");
  return (
    <div className="flex h-full flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <p className="min-w-0 flex-1 truncate font-mono text-sm">
          {path}
          {dirty && <span className="ml-2 text-xs text-warning-foreground">{create ? "new file" : "edited"}</span>}
        </p>
        {!create && (
          <Button size="sm" variant="outline" onClick={onHistory}>
            <History />
            History
          </Button>
        )}
        {!create && (
          <ConfirmButton
            label="Delete"
            icon={Trash2}
            title={`Delete ${path}?`}
            description="The deletion is a commit like any other: testing builds it and it can be reverted."
            onConfirm={() => save.mutate({ message: `Delete ${path}`, changes: [{ path, content: null }] })}
            disabled={save.isPending}
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
        {isNix ? (
          <NixSource value={draft} onChange={setDraft} onSave={() => setCommitting(true)} />
        ) : (
          <NixEditor value={draft} onChange={setDraft} onSave={() => setCommitting(true)} language={plain} />
        )}
      </div>
      <CommitDialog
        open={committing}
        suggestion={`${create ? "Add" : "Update"} ${path}`}
        pending={save.isPending}
        onOpenChange={setCommitting}
        onCommit={(message) => save.mutate({ message, changes: [{ path, content: draft }] })}
      />
    </div>
  );
}

type SourceProps = { value: string; onChange: (value: string) => void; onSave: () => void };

// Nix files show syntax errors as you type.
function NixSource({ value, onChange, onSave }: SourceProps) {
  const { problem } = useSyntaxCheck(value);
  return <NixEditor value={value} onChange={onChange} onSave={onSave} problem={problem} />;
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

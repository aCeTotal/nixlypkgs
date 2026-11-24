import { useMutation, useQuery } from "@tanstack/react-query";
import { Undo2 } from "lucide-react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { dateTime } from "@/format/time";
import { ConfirmButton } from "@/shell/confirm-button";
import { Skeleton } from "@/ui/skeleton";
import { DiffView } from "./diff-view";
import { commitQuery, revertCommit, treeQuery } from "./queries";

export function CommitView({ sha, onPath }: { sha: string; onPath: (path: string) => void }) {
  const { data } = useQuery(commitQuery(sha));
  const head = useQuery(treeQuery("")).data?.head;
  const revert = useMutation({
    mutationFn: () => revertCommit(sha, head ?? ""),
    onSuccess: (result) => toast.success(`Reverted in ${shortSha(result.sha)}; testing builds it next`),
  });
  if (!data) return <Skeleton className="h-64" />;
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start gap-3">
        <div className="min-w-0 flex-1 space-y-1">
          <p className="font-medium">{data.subject}</p>
          <p className="text-xs text-muted-foreground">
            <span className="font-mono">{shortSha(data.sha)}</span> · {data.author} · {dateTime(data.time)}
            {data.parent && (
              <>
                {" "}
                · parent <span className="font-mono">{shortSha(data.parent)}</span>
              </>
            )}
          </p>
        </div>
        {data.parent && (
          <ConfirmButton
            label="Revert"
            icon={Undo2}
            title="Revert this commit?"
            description="A new commit undoes it on main. Testing builds that commit like any other."
            onConfirm={() => revert.mutate()}
            disabled={!head || revert.isPending}
          />
        )}
      </div>
      {data.body && <pre className="rounded-lg bg-muted/40 p-3 font-sans text-sm whitespace-pre-wrap">{data.body}</pre>}
      {data.truncated && <p className="text-sm text-muted-foreground">The diff is larger than 2 MiB; read it with git.</p>}
      {data.files.map((file) => (
        <DiffView key={file.path} file={file} onPath={onPath} />
      ))}
    </div>
  );
}

import { useInfiniteQuery } from "@tanstack/react-query";
import { FileCode, GitCommitVertical, X } from "lucide-react";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { Button } from "@/ui/button";
import { Card, CardContent } from "@/ui/card";
import { cn } from "@/ui/cn";
import { Skeleton } from "@/ui/skeleton";
import { CommitView } from "./commit-view";
import { logQuery } from "./queries";

type HistoryViewProps = {
  path: string;
  commit: string | undefined;
  onPath: (path: string) => void;
  onCommit: (sha: string) => void;
};

export function HistoryView({ path, commit, onPath, onCommit }: HistoryViewProps) {
  const log = useInfiniteQuery(logQuery(path));
  const commits = log.data?.pages.flatMap((page) => page.commits) ?? [];
  return (
    <Card className="overflow-hidden py-0">
      <CardContent className="grid p-0 lg:grid-cols-[24rem_1fr]">
        <nav className="max-h-[75vh] overflow-y-auto border-b bg-muted/20 p-2 lg:border-r lg:border-b-0">
          {path && (
            <div className="mb-2 flex items-center gap-2 rounded-md bg-primary/10 px-2 py-1 text-xs text-primary">
              <FileCode className="size-3.5 shrink-0" />
              <span className="min-w-0 flex-1 truncate font-mono">{path}</span>
              <Button size="icon" variant="ghost" className="size-5" onClick={() => onPath("")} aria-label="Show all commits">
                <X />
              </Button>
            </div>
          )}
          {!log.data && <Skeleton className="h-40" />}
          <ul>
            {commits.map((entry) => (
              <li key={entry.sha}>
                <button
                  type="button"
                  onClick={() => onCommit(entry.sha)}
                  className={cn(
                    "flex w-full items-start gap-2 rounded-md px-2 py-1.5 text-left hover:bg-muted",
                    entry.sha === commit && "bg-primary/10",
                  )}
                >
                  <GitCommitVertical className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm">{entry.subject}</span>
                    <span className="block truncate text-xs text-muted-foreground">
                      <span className="font-mono">{shortSha(entry.sha)}</span> · {entry.author} · {timeAgo(entry.time)}
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
          {log.hasNextPage && (
            <Button variant="link" size="sm" onClick={() => void log.fetchNextPage()} disabled={log.isFetchingNextPage}>
              Show older
            </Button>
          )}
        </nav>
        <div className="max-h-[75vh] min-w-0 overflow-y-auto p-4">
          {commit ? <CommitView sha={commit} onPath={onPath} /> : <p className="text-sm text-muted-foreground">Pick a commit to see what it changed.</p>}
        </div>
      </CardContent>
    </Card>
  );
}

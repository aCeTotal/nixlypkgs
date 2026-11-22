import { useMutation, useSuspenseInfiniteQuery } from "@tanstack/react-query";
import { CircleCheck, CircleX, LoaderCircle, RotateCcw } from "lucide-react";
import { Fragment } from "react";
import { formatDuration, secondsBetween } from "@/format/duration";
import { shortSha } from "@/format/sha";
import { dateTime, timeAgo } from "@/format/time";
import { PageHeader } from "@/shell/page-header";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/ui/table";
import { commitsQuery, retryCommit, type EvalState } from "./queries";

const states: Record<EvalState, { icon: typeof CircleCheck; tone: string; label: string }> = {
  done: { icon: CircleCheck, tone: "text-success", label: "Evaluert" },
  evaluating: { icon: LoaderCircle, tone: "text-info animate-spin", label: "Evaluerer" },
  failed: { icon: CircleX, tone: "text-destructive", label: "Feilet" },
};

export function CommitsPage() {
  const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useSuspenseInfiniteQuery(commitsQuery);
  const retry = useMutation({ mutationFn: retryCommit });
  const commits = data.pages.flatMap((page) => page.items);
  const newest = commits[0]?.sha;
  return (
    <div className="space-y-4">
      <PageHeader title="Commits" description="Hver commit på branchen evalueres; endrede derivasjoner blir nye versjoner." />
      <div className="overflow-hidden rounded-xl border bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-8" />
              <TableHead>Commit</TableHead>
              <TableHead>Forfatter</TableHead>
              <TableHead className="text-right">Endret</TableHead>
              <TableHead className="text-right">Attributter</TableHead>
              <TableHead className="text-right">Evaluering</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {commits.map((commit) => {
              const state = states[commit.evalState];
              return (
                <Fragment key={commit.sha}>
                  <TableRow>
                    <TableCell>
                      <state.icon className={`size-4 ${state.tone}`} aria-label={state.label} />
                    </TableCell>
                    <TableCell className="max-w-xl">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-mono text-xs text-muted-foreground">{shortSha(commit.sha)}</span>
                        <span className="truncate font-medium">{commit.subject}</span>
                        {commit.publishedFor.map((type) => (
                          <Badge key={type} variant="secondary">
                            {type}
                          </Badge>
                        ))}
                      </div>
                      <p className="text-xs text-muted-foreground" title={dateTime(commit.committedAt)}>
                        {timeAgo(commit.committedAt)}
                      </p>
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">{commit.author}</TableCell>
                    <TableCell className="text-right tabular-nums">{commit.changed > 0 ? commit.changed : "–"}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {commit.attrs}
                      {commit.failedAttrs > 0 && <span className="text-destructive"> ({commit.failedAttrs} feil)</span>}
                    </TableCell>
                    <TableCell className="text-right text-sm text-muted-foreground tabular-nums">
                      {formatDuration(secondsBetween(commit.evalStartedAt, commit.evalFinishedAt))}
                    </TableCell>
                  </TableRow>
                  {commit.evalError && (
                    <TableRow className="hover:bg-transparent">
                      <TableCell />
                      <TableCell colSpan={5}>
                        <pre className="max-h-48 overflow-auto rounded-lg bg-danger-soft p-3 font-mono text-xs whitespace-pre-wrap text-destructive">
                          {commit.evalError}
                        </pre>
                        {commit.sha === newest && (
                          <Button size="sm" variant="outline" className="mt-2" onClick={() => retry.mutate(commit.sha)}>
                            <RotateCcw />
                            Evaluer på nytt
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  )}
                </Fragment>
              );
            })}
          </TableBody>
        </Table>
      </div>
      {hasNextPage && (
        <div className="flex justify-center">
          <Button variant="outline" onClick={() => void fetchNextPage()} disabled={isFetchingNextPage}>
            Vis eldre commits
          </Button>
        </div>
      )}
    </div>
  );
}

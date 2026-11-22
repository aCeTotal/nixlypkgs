import { useMutation } from "@tanstack/react-query";
import { GitBranch, History, Pause, Play, RefreshCw, Search } from "lucide-react";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import { watcherAction, type WatcherPhase, type WatcherStatus } from "./queries";

const phases: Record<WatcherPhase, { label: string; tone: string }> = {
  idle: { label: "Venter på nye commits", tone: "bg-success" },
  fetching: { label: "Henter fra git", tone: "bg-info" },
  evaluating: { label: "Evaluerer commit", tone: "bg-info" },
  backfilling: { label: "Går gjennom historikk", tone: "bg-chart-5" },
  paused: { label: "Pauset", tone: "bg-warning" },
};

export function WatcherCard({ watcher }: { watcher: WatcherStatus }) {
  const act = useMutation({ mutationFn: watcherAction });
  const phase = phases[watcher.phase];
  const busy = watcher.phase !== "idle" && watcher.phase !== "paused";
  const backfill = Math.min(100, (watcher.backfillSteps / watcher.backfillLimit) * 100);
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <GitBranch className="size-4 text-primary" />
          Overvåker
        </CardTitle>
        <CardDescription>Evaluerer hver commit og legger nye derivasjoner i byggekøen.</CardDescription>
        <CardAction className="flex gap-1.5">
          <Button size="sm" variant="outline" onClick={() => act.mutate("poll")} disabled={act.isPending}>
            <RefreshCw />
            Sjekk nå
          </Button>
          {watcher.phase === "paused" ? (
            <Button size="sm" onClick={() => act.mutate("resume")} disabled={act.isPending}>
              <Play />
              Gjenoppta
            </Button>
          ) : (
            <Button size="sm" variant="outline" onClick={() => act.mutate("pause")} disabled={act.isPending}>
              <Pause />
              Pause
            </Button>
          )}
        </CardAction>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center gap-3">
          <span className="relative flex size-3">
            {busy && <span className={cn("absolute inline-flex size-full animate-ping rounded-full opacity-60", phase.tone)} />}
            <span className={cn("relative inline-flex size-3 rounded-full", phase.tone)} />
          </span>
          <div className="min-w-0">
            <p className="font-medium">{phase.label}</p>
            {watcher.commit && (
              <p className="truncate text-sm text-muted-foreground">
                <span className="font-mono">{shortSha(watcher.commit.sha)}</span> · {watcher.commit.subject}
              </p>
            )}
          </div>
        </div>
        <dl className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <dt className="text-muted-foreground">Siste branch-hode</dt>
            <dd className="font-mono">{shortSha(watcher.head)}</dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Sist sjekket</dt>
            <dd>{timeAgo(watcher.lastPoll)}</dd>
          </div>
        </dl>
        <div className="space-y-1.5">
          <div className="flex items-center justify-between text-sm">
            <span className="flex items-center gap-1.5 text-muted-foreground">
              <History className="size-3.5" />
              Historikk for siste versjoner
            </span>
            <span className="tabular-nums">
              {watcher.backfillDone ? "Ferdig" : `${watcher.backfillSteps}/${watcher.backfillLimit}`}
            </span>
          </div>
          <div className="h-1.5 overflow-hidden rounded-full bg-muted">
            <div className="h-full bg-chart-5 transition-[width]" style={{ width: `${watcher.backfillDone ? 100 : backfill}%` }} />
          </div>
          {watcher.backfillDone && (
            <Button size="xs" variant="ghost" onClick={() => act.mutate("backfill")} disabled={act.isPending}>
              <Search />
              Søk lenger tilbake
            </Button>
          )}
        </div>
        {watcher.lastError && (
          <pre className="max-h-32 overflow-auto rounded-lg bg-danger-soft p-3 font-mono text-xs whitespace-pre-wrap text-destructive">
            {watcher.lastError}
          </pre>
        )}
      </CardContent>
    </Card>
  );
}

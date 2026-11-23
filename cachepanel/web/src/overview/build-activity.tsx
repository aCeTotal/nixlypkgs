import { Link } from "@tanstack/react-router";
import { Hammer, Hourglass, ListChecks } from "lucide-react";
import { BuildProgress } from "@/builds/build-progress";
import { useAllProgress } from "@/builds/progress-store";
import { StateBadge } from "@/builds/state-badge";
import { formatDuration } from "@/format/duration";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { Badge } from "@/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import type { FinishedBuild, QueuedBuild } from "./queries";

function PackageLink({ attr, children }: { attr: string; children: React.ReactNode }) {
  return (
    <Link to="/packages/$attr" params={{ attr }} className="truncate font-medium hover:text-primary hover:underline">
      {children}
    </Link>
  );
}

export function RunningBuilds() {
  const running = useAllProgress();
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Hammer className="size-4 text-info" />
          Building now
        </CardTitle>
        <CardDescription>{running.length === 0 ? "Nothing is building." : `${running.length} concurrent builds`}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {running.map((progress) => (
          <div key={progress.versionId} className="space-y-1.5">
            <div className="flex items-center justify-between gap-3 text-sm">
              <PackageLink attr={progress.attr}>{progress.attr}</PackageLink>
              <span className="truncate text-xs text-muted-foreground">{progress.name}</span>
            </div>
            <BuildProgress versionId={progress.versionId} />
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

export function QueueCard({ queue }: { queue: QueuedBuild[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Hourglass className="size-4 text-warning-foreground" />
          Up next
        </CardTitle>
        <CardDescription>{queue.length === 0 ? "The queue is empty." : "Newest commit first, manual builds ahead."}</CardDescription>
      </CardHeader>
      <CardContent className="divide-y">
        {queue.map((item) => (
          <div key={item.id} className="flex items-center justify-between gap-3 py-2 text-sm">
            <div className="min-w-0">
              <PackageLink attr={item.attr}>{item.attr}</PackageLink>
              <p className="truncate text-xs text-muted-foreground">{item.name}</p>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              {item.priority && <Badge variant="secondary">Manual</Badge>}
              <span className="font-mono text-xs text-muted-foreground">{shortSha(item.commit)}</span>
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

export function RecentCard({ recent }: { recent: FinishedBuild[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <ListChecks className="size-4 text-success" />
          Recent builds
        </CardTitle>
        <CardDescription>Finished, failed and cancelled builds.</CardDescription>
      </CardHeader>
      <CardContent className="divide-y">
        {recent.map((item) => (
          <div key={item.id} className="flex items-center justify-between gap-3 py-2 text-sm">
            <div className="min-w-0">
              <PackageLink attr={item.attr}>{item.attr}</PackageLink>
              <p className="truncate text-xs text-muted-foreground">
                {item.name} · {timeAgo(item.finishedAt)} · {formatDuration(item.seconds)}
              </p>
            </div>
            <StateBadge state={item.state} />
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

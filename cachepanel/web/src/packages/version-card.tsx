import { useMutation } from "@tanstack/react-query";
import { Ban, Hammer, Lock, LockOpen, ScrollText, Trash2 } from "lucide-react";
import { useState } from "react";
import { BuildProgress } from "@/builds/build-progress";
import { StateBadge } from "@/builds/state-badge";
import { formatBytes } from "@/format/bytes";
import { formatDuration, secondsBetween } from "@/format/duration";
import { shortSha } from "@/format/sha";
import { dateTime, timeAgo } from "@/format/time";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Card, CardContent } from "@/ui/card";
import { cn } from "@/ui/cn";
import { BranchBadge } from "@/profiles/branch-badge";
import { ConfirmButton } from "@/shell/confirm-button";
import { LogViewer } from "./log-viewer";
import { selectVersion, versionAction, type PackageDetail, type Version } from "./queries";

type VersionCardProps = { pkg: PackageDetail; version: Version; newest: boolean };

export function VersionCard({ pkg, version, newest }: VersionCardProps) {
  const [showLog, setShowLog] = useState(version.state === "failed" || version.state === "building");
  const act = useMutation({ mutationFn: (action: "build" | "cancel" | "drop") => versionAction(version.id, action) });
  const choose = useMutation({ mutationFn: (id: number | null) => selectVersion(pkg.attr, id) });
  const selected = pkg.selectedVersionId === version.id;
  const stable = pkg.stableVersionId === version.id;
  const running = version.state === "building" || version.state === "queued";
  const rebuildable = version.state === "pending" || version.state === "failed" || version.state === "cancelled";
  return (
    <Card className={cn(selected && "ring-2 ring-primary")}>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0 space-y-1">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="font-semibold">{version.name}</h3>
              <StateBadge state={version.state} />
              {newest && <Badge variant="outline">Newest</Badge>}
              {selected && (
                <Badge>
                  <Lock />
                  Selected
                </Badge>
              )}
              {stable && <BranchBadge branch="stable" />}
            </div>
            <p className="text-sm text-muted-foreground">
              Commit <span className="font-mono">{shortSha(version.first.sha)}</span>
              {version.first.sha !== version.last.sha && (
                <>
                  {" → "}
                  <span className="font-mono">{shortSha(version.last.sha)}</span>
                </>
              )}
              {" · "}
              {version.last.subject}
            </p>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {pkg.pinnable && version.state === "cached" && !selected && (
              <Button size="sm" onClick={() => choose.mutate(version.id)} disabled={choose.isPending}>
                <Lock />
                Use this
              </Button>
            )}
            {selected && (
              <Button size="sm" variant="outline" onClick={() => choose.mutate(null)} disabled={choose.isPending}>
                <LockOpen />
                Follow the system
              </Button>
            )}
            {rebuildable && (
              <Button size="sm" variant="outline" onClick={() => act.mutate("build")} disabled={act.isPending}>
                <Hammer />
                {version.state === "pending" ? "Build now" : "Build again"}
              </Button>
            )}
            {running && (
              <Button size="sm" variant="outline" onClick={() => act.mutate("cancel")} disabled={act.isPending}>
                <Ban />
                Cancel
              </Button>
            )}
            {!selected && !stable && version.state !== "pending" && version.state !== "building" && (
              <ConfirmButton
                label="Delete from cache"
                icon={Trash2}
                title={`Delete ${version.name} from the cache?`}
                description="The build is removed from the server at the next cleanup. The version can be built again later."
                onConfirm={() => act.mutate("drop")}
              />
            )}
            <Button size="sm" variant="ghost" onClick={() => setShowLog(!showLog)}>
              <ScrollText />
              Log
            </Button>
          </div>
        </div>
        {version.state === "building" && <BuildProgress versionId={version.id} />}
        <dl className="grid gap-3 text-sm sm:grid-cols-4">
          <Fact label="Commit time" value={dateTime(version.last.time)} />
          <Fact label="Built" value={version.finishedAt ? timeAgo(version.finishedAt) : "–"} />
          <Fact label="Build time" value={formatDuration(secondsBetween(version.startedAt, version.finishedAt))} />
          <Fact label="Size" value={formatBytes(version.closureBytes)} />
        </dl>
        <div className="space-y-1 rounded-lg bg-muted/50 p-3 font-mono text-xs">
          <p className="truncate text-muted-foreground">{version.drvPath}</p>
          {Object.entries(version.outputs).map(([output, path]) => (
            <p key={output} className="truncate">
              <span className="text-primary">{output}</span> {path}
            </p>
          ))}
        </div>
        {version.error && (
          <pre className="max-h-40 overflow-auto rounded-lg bg-danger-soft p-3 font-mono text-xs whitespace-pre-wrap text-destructive">
            {version.error}
          </pre>
        )}
        {showLog && <LogViewer versionId={version.id} live={running} />}
      </CardContent>
    </Card>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}

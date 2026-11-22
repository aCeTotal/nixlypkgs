import { useEffect, useState } from "react";
import { formatDuration } from "@/format/duration";
import { cn } from "@/ui/cn";
import { useProgress, type Progress } from "./progress-store";

const tick = 1_000;
const ceiling = 0.99;

function useNow(active: boolean) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return;
    const timer = window.setInterval(() => setNow(Date.now()), tick);
    return () => window.clearInterval(timer);
  }, [active]);
  return now;
}

// Known duration beats step counts.
function fraction(progress: Progress, elapsed: number) {
  if (progress.expectedSeconds > 0) return Math.min(ceiling, elapsed / progress.expectedSeconds);
  const done = progress.builds.done + progress.paths.done;
  const expected = progress.builds.expected + progress.paths.expected;
  return expected > 0 ? Math.min(ceiling, done / expected) : 0;
}

export function BuildProgress({ versionId, compact }: { versionId: number; compact?: boolean }) {
  const progress = useProgress(versionId);
  const now = useNow(progress !== undefined);
  if (!progress) return <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted"><div className="shimmer h-full w-full" /></div>;
  const elapsed = (now - new Date(progress.startedAt).getTime()) / 1000;
  const share = fraction(progress, elapsed);
  const remaining = progress.expectedSeconds > 0 ? progress.expectedSeconds - elapsed : null;
  return (
    <div className="min-w-0 space-y-1.5">
      <div className="relative h-1.5 w-full overflow-hidden rounded-full bg-muted">
        <div
          className="h-full rounded-full bg-gradient-to-r from-primary to-chart-5 transition-[width] duration-700"
          style={{ width: `${Math.max(3, share * 100)}%` }}
        />
        <div className="shimmer absolute inset-0" />
      </div>
      <div className={cn("flex items-center justify-between gap-3 text-xs text-muted-foreground tabular-nums", compact && "text-[0.7rem]")}>
        <span className="truncate">
          {progress.activity || "Forbereder"}
          {progress.phase && ` · ${progress.phase}`}
        </span>
        <span className="shrink-0">
          {progress.builds.expected > 0 && `${progress.builds.done}/${progress.builds.expected} bygg · `}
          {progress.paths.expected > 0 && `${progress.paths.done}/${progress.paths.expected} hentet · `}
          {formatDuration(elapsed)}
          {remaining !== null && remaining > 0 && ` · ~${formatDuration(remaining)} igjen`}
        </span>
      </div>
      {!compact && progress.line && <p className="truncate font-mono text-[0.7rem] text-muted-foreground/80">{progress.line}</p>}
    </div>
  );
}

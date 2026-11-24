import { useMutation, useSuspenseQuery } from "@tanstack/react-query";
import { CircleCheck, CircleX, Hourglass, LoaderCircle, RefreshCw, type LucideIcon } from "lucide-react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import { Switch } from "@/ui/switch";
import { setAutoUpdate, updateQuery, type UpdatePhase } from "./queries";

const phases: Record<UpdatePhase, { label: string; icon: LucideIcon; tone: string }> = {
  building: { label: "Building the server's new system", icon: LoaderCircle, tone: "text-primary" },
  waiting: { label: "Built; waiting until nothing is building", icon: Hourglass, tone: "text-warning-foreground" },
  switching: { label: "Switching to the new panel", icon: LoaderCircle, tone: "text-primary" },
  done: { label: "Updated", icon: CircleCheck, tone: "text-success" },
  failed: { label: "Failed and rolled back, database included", icon: CircleX, tone: "text-destructive" },
  superseded: { label: "Skipped for a newer commit", icon: RefreshCw, tone: "text-muted-foreground" },
};

// The store hash names a build.
const build = (path: string) => path.replace("/nix/store/", "").slice(0, 8);

export function UpdateCard() {
  const { data } = useSuspenseQuery(updateQuery);
  const toggle = useMutation({
    mutationFn: setAutoUpdate,
    onSuccess: (_, enabled) => toast.success(enabled ? "The panel updates itself" : "Self-update paused"),
  });
  const current = data.newest === null || data.newest.out === data.running;
  const phase = data.status ? phases[data.status.phase] : null;
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <RefreshCw className="size-4 text-primary" />
          Panel updates
        </CardTitle>
        <CardDescription>
          A push that changes the panel rebuilds this server once nothing is building. Failures roll back, database included.
        </CardDescription>
        {data.configured && (
          <CardAction className="flex items-center gap-2 text-sm">
            <label htmlFor="self-update">Automatic</label>
            <Switch id="self-update" checked={data.enabled} onCheckedChange={(enabled) => toggle.mutate(enabled)} disabled={toggle.isPending} />
          </CardAction>
        )}
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        {!data.configured && <p className="text-muted-foreground">Set selfUpdate.flake in the module to let the panel update itself.</p>}
        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5">
          <dt className="text-muted-foreground">Running</dt>
          <dd className="font-mono">{build(data.running)}</dd>
          <dt className="text-muted-foreground">Newest</dt>
          <dd>
            {data.newest ? (
              <span className={cn("font-mono", !current && "text-primary")}>
                {build(data.newest.out)} · {shortSha(data.newest.rev)}
                {current ? " · running" : " · ready"}
              </span>
            ) : (
              <span className="text-muted-foreground">Not built yet</span>
            )}
          </dd>
          <dt className="text-muted-foreground">Server</dt>
          <dd>{data.idle ? "Idle" : "Busy building"}</dd>
        </dl>
        {data.status && phase && (
          <details className="rounded-lg border bg-muted/30 p-3">
            <summary className="flex cursor-pointer items-center gap-2">
              <phase.icon className={cn("size-4 shrink-0", phase.tone, phase.icon === LoaderCircle && "animate-spin")} />
              <span className="flex-1">{phase.label}</span>
              <span className="font-mono text-xs text-muted-foreground">{shortSha(data.status.rev)}</span>
              <span className="text-xs text-muted-foreground">{timeAgo(data.status.at)}</span>
            </summary>
            <pre className="mt-3 max-h-72 overflow-auto font-mono text-xs whitespace-pre-wrap">{data.status.log || "No output."}</pre>
          </details>
        )}
      </CardContent>
    </Card>
  );
}

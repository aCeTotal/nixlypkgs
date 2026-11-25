import { useMutation, useQuery } from "@tanstack/react-query";
import { GitBranch, RefreshCw, TriangleAlert } from "lucide-react";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Card, CardContent } from "@/ui/card";
import { Spinner } from "@/ui/spinner";
import { checkUpstream, upstreamQuery, type UpstreamState } from "./queries";

const labels: Record<UpstreamState, string> = { current: "Up to date", updating: "Pinning the newest commit", failed: "Update failed" };

// Upstream commits land in testing.
export function UpstreamCard({ attr }: { attr: string }) {
  const tracked = useQuery(upstreamQuery).data?.find((each) => each.attr === attr);
  const check = useMutation({ mutationFn: checkUpstream });
  if (!tracked) return null;
  return (
    <Card>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
          <div className="flex min-w-0 flex-1 items-center gap-3">
            <GitBranch className="size-5 shrink-0 text-primary" />
            <div className="min-w-0">
              <a href={tracked.url} target="_blank" rel="noreferrer" className="block truncate font-medium hover:text-primary hover:underline">
                {tracked.url.replace(/^https:\/\//, "")}
              </a>
              <p className="text-sm text-muted-foreground">
                Follows <span className="font-mono">{tracked.follows}</span> · pinned {tracked.version} at{" "}
                <span className="font-mono">{shortSha(tracked.rev)}</span>
              </p>
            </div>
          </div>
          <Badge variant={tracked.state === "failed" ? "destructive" : "outline"} className="gap-1.5">
            {tracked.state === "updating" && <Spinner className="size-3" />}
            {labels[tracked.state]}
          </Badge>
          <span className="text-sm text-muted-foreground">checked {timeAgo(tracked.checkedAt)}</span>
          <Button size="sm" variant="outline" onClick={() => check.mutate()} disabled={check.isPending}>
            <RefreshCw />
            Check now
          </Button>
        </div>
        {tracked.error && (
          <div className="flex gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm">
            <TriangleAlert className="mt-0.5 size-4 shrink-0 text-destructive" />
            <pre className="max-h-40 min-w-0 flex-1 overflow-auto font-mono text-xs whitespace-pre-wrap">{tracked.error}</pre>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

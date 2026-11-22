import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";
import { seedProgress, type Progress } from "@/builds/progress-store";
import type { BuildState } from "@/packages/queries";

export type WatcherPhase = "idle" | "fetching" | "evaluating" | "backfilling" | "paused";

export type WatcherStatus = {
  phase: WatcherPhase;
  commit: { sha: string; subject: string; time: string } | null;
  head: string;
  started: string | null;
  lastPoll: string | null;
  lastError: string;
  backfillSteps: number;
  backfillLimit: number;
  backfillDone: boolean;
};

export type QueuedBuild = { id: number; attr: string; name: string; commit: string; priority: boolean };
export type FinishedBuild = { id: number; attr: string; name: string; state: BuildState; finishedAt: string; seconds: number | null };

export type Overview = {
  cache: {
    packages: number;
    states: Partial<Record<BuildState, number>>;
    closureBytes: number;
    queue: QueuedBuild[];
    recent: FinishedBuild[];
  };
  watcher: WatcherStatus;
  builds: Progress[];
  disk: { total: number; free: number };
  keep: number;
};

export const overviewQuery = queryOptions({
  queryKey: ["overview"],
  queryFn: async () => {
    const overview = await api<Overview>("/overview");
    seedProgress(overview.builds);
    return overview;
  },
  refetchInterval: 30_000,
});

export const watcherAction = (action: "pause" | "resume" | "poll" | "backfill") =>
  api(`/watcher/${action}`, { method: "POST" });

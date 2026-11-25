import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type UpstreamState = "current" | "updating" | "failed";

// A pin and its tracking status.
export type Tracked = {
  attr: string;
  url: string;
  follows: string;
  rev: string;
  version: string;
  latestRev: string | null;
  state: UpstreamState;
  error: string | null;
  checkedAt: string | null;
  committedAt: string | null;
};

export const upstreamQuery = queryOptions({ queryKey: ["upstream"], queryFn: () => api<Tracked[]>("/upstream") });

export const checkUpstream = () => api("/upstream/check", { method: "POST" });

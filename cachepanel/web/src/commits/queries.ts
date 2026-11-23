import { infiniteQueryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type EvalState = "evaluating" | "done" | "failed";

export type Commit = {
  sha: string;
  position: number;
  subject: string;
  author: string;
  committedAt: string;
  evalState: EvalState;
  evalStartedAt: string;
  evalFinishedAt: string | null;
  evalError: string | null;
  attrs: number;
  failedAttrs: number;
  changed: number;
  stableFor: string[];
  testingFor: string[];
};

type Page = { items: Commit[]; next: number | null };

export const commitsQuery = infiniteQueryOptions({
  queryKey: ["commits"],
  queryFn: ({ pageParam }) => api<Page>(`/commits${pageParam ? `?before=${pageParam}` : ""}`),
  initialPageParam: 0,
  getNextPageParam: (page) => page.next ?? undefined,
});

export const retryCommit = (sha: string) => api(`/commits/${sha}/retry`, { method: "POST" });

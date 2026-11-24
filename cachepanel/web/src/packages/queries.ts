import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type BuildState = "pending" | "queued" | "building" | "cached" | "failed" | "cancelled";

export type CommitRef = { sha: string; subject: string; author: string; time: string };

export type VersionSummary = { id: number; name: string; state: BuildState; commit: string; closureBytes: number | null };

export type PackageSummary = {
  attr: string;
  autoBuild: boolean;
  present: boolean;
  pinnable: boolean;
  evalError: string | null;
  expectedSeconds: number | null;
  selectedVersionId: number | null;
  stableVersionId: number | null;
  versions: VersionSummary[];
};

export type Version = {
  id: number;
  name: string;
  drvPath: string;
  outputs: Record<string, string>;
  state: BuildState;
  queuedAt: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  closureBytes: number | null;
  error: string | null;
  first: CommitRef;
  last: CommitRef;
};

export type PackageDetail = Omit<PackageSummary, "versions"> & { versions: Version[] };

export const packagesQuery = queryOptions({
  queryKey: ["packages"],
  queryFn: () => api<PackageSummary[]>("/packages"),
});

export const packageQuery = (attr: string) =>
  queryOptions({
    queryKey: ["package", attr],
    queryFn: () => api<PackageDetail>(`/packages/${encodeURIComponent(attr)}`),
  });

export const buildLogQuery = (id: number, live: boolean) =>
  queryOptions({
    queryKey: ["build-log", id],
    queryFn: async ({ signal }) => (await api<{ log: string }>(`/versions/${id}/log`, { signal })).log,
    refetchInterval: live ? 2_000 : false,
  });

export const setAutoBuild = (attr: string, enabled: boolean) =>
  api(`/packages/${encodeURIComponent(attr)}/auto`, { method: "PUT", body: { enabled } });

export const selectVersion = (attr: string, versionId: number | null) =>
  api(`/packages/${encodeURIComponent(attr)}/selection`, { method: "PUT", body: { versionId } });

export const versionAction = (id: number, action: "build" | "cancel" | "drop") =>
  action === "drop" ? api(`/versions/${id}/cache`, { method: "DELETE" }) : api(`/versions/${id}/${action}`, { method: "POST" });

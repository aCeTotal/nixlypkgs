import { infiniteQueryOptions, queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type PushKey = { id: number; name: string; type: string; fingerprint: string; createdAt: string };

export type Source = { clone: string; remote: string; keys: PushKey[] };

export type Entry = { name: string; path: string; dir: boolean; size: number };

export type Listing = { head: string; entries: Entry[] };

export type Blob = { head: string; path: string; size: number; binary: boolean; text: string };

export type SourceCommit = { sha: string; author: string; time: string; subject: string };

export type FileDiff = { path: string; oldPath: string; status: "A" | "M" | "D" | "R" | "C" | "T"; patch: string };

export type CommitDetails = SourceCommit & { body: string; parent: string; files: FileDiff[]; truncated: boolean };

export type FileChange = { path: string; content: string | null };

export const sourceQuery = queryOptions({ queryKey: ["source"], queryFn: () => api<Source>("/source") });

export const treeQuery = (path: string) =>
  queryOptions({ queryKey: ["source", "tree", path], queryFn: () => api<Listing>(`/source/tree?path=${encodeURIComponent(path)}`) });

export const fileQuery = (path: string) =>
  queryOptions({ queryKey: ["source", "file", path], queryFn: () => api<Blob>(`/source/file?path=${encodeURIComponent(path)}`) });

export const logQuery = (path: string) =>
  infiniteQueryOptions({
    queryKey: ["source", "log", path],
    queryFn: ({ pageParam }) =>
      api<{ commits: SourceCommit[]; more: boolean }>(`/source/log?path=${encodeURIComponent(path)}&skip=${pageParam}`),
    initialPageParam: 0,
    getNextPageParam: (page, pages) => (page.more ? pages.reduce((sum, each) => sum + each.commits.length, 0) : undefined),
  });

export const commitQuery = (sha: string) =>
  queryOptions({ queryKey: ["source", "commit", sha], queryFn: () => api<CommitDetails>(`/source/commits/${sha}`), staleTime: Infinity });

export const commitChanges = (body: { base: string; message: string; changes: FileChange[] }) =>
  api<{ sha: string }>("/source/commits", { method: "POST", body });

export const revertCommit = (sha: string, base: string) =>
  api<{ sha: string }>(`/source/commits/${sha}/revert`, { method: "POST", body: { base } });

export const addKey = (body: { name: string; publicKey: string }) => api<PushKey>("/source/keys", { method: "POST", body });

export const removeKey = (id: number) => api(`/source/keys/${id}`, { method: "DELETE" });

export type FlakeInput = { name: string; source: string; ref: string; rev: string; modified: string | null };

export const inputsQuery = queryOptions({
  queryKey: ["source", "inputs"],
  queryFn: () => api<{ head: string; inputs: FlakeInput[] }>("/source/inputs"),
});

export const updateInputs = (base: string, inputs: string[]) =>
  api<{ sha: string }>("/source/inputs/update", { method: "POST", body: { base, inputs } });

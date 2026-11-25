import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";
import type { CheckState } from "@/profiles/queries";
import type { SourceCommit } from "@/source/queries";

export type ModuleUser = { name: string; title: string; checkState: CheckState };

export type ModuleEntry = { slug: string; title: string; description: string; required: boolean };

export type ModuleSummary = ModuleEntry & {
  position: number;
  lines: number;
  changedAt: string | null;
  usedBy: ModuleUser[];
};

export type ModuleDetail = ModuleSummary & { head: string; source: string; history: SourceCommit[] };

export type ModuleDraft = ModuleEntry & { base: string; source: string; message: string };


export const modulesQuery = queryOptions({
  queryKey: ["modules"],
  queryFn: () => api<{ head: string; modules: ModuleSummary[] }>("/modules"),
});

export const moduleQuery = (slug: string) =>
  queryOptions({ queryKey: ["module", slug], queryFn: () => api<ModuleDetail>(`/modules/${slug}`) });

export const revisionSource = (slug: string, sha: string) => api<{ source: string }>(`/modules/${slug}/revisions/${sha}`);

export const createModule = (body: ModuleDraft) => api<{ sha: string }>("/modules", { method: "POST", body });

export const saveModule = (body: ModuleDraft) => api<{ sha: string }>(`/modules/${body.slug}`, { method: "PUT", body });

export const deleteModule = (slug: string, base: string, message: string) =>
  api(`/modules/${slug}`, { method: "DELETE", body: { base, message } });


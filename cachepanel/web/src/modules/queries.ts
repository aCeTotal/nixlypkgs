import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";
import type { CheckState } from "@/profiles/queries";

export type ModuleUser = { name: string; title: string; checkState: CheckState };

export type ModuleSummary = {
  id: number;
  slug: string;
  title: string;
  description: string;
  required: boolean;
  position: number;
  revision: number;
  updatedAt: string;
  lines: number;
  usedBy: ModuleUser[];
};

export type ModuleDetail = Omit<ModuleSummary, "lines"> & {
  source: string;
  revisions: { revision: number; createdAt: string }[];
};

export type ModuleDraft = { slug: string; title: string; description: string; source: string; required: boolean };

// Empty error means valid Nix.
export type SyntaxProblem = { error: string; line?: number; column?: number };

export const modulesQuery = queryOptions({ queryKey: ["modules"], queryFn: () => api<ModuleSummary[]>("/modules") });

export const moduleQuery = (id: number) =>
  queryOptions({ queryKey: ["module", id], queryFn: () => api<ModuleDetail>(`/modules/${id}`) });

export const revisionSource = (id: number, revision: number) =>
  api<{ source: string }>(`/modules/${id}/revisions/${revision}`);

export const createModule = (body: ModuleDraft) => api<{ id: number }>("/modules", { method: "POST", body });

export const saveModule = (id: number, body: ModuleDraft) => api(`/modules/${id}`, { method: "PUT", body });

export const deleteModule = (id: number) => api(`/modules/${id}`, { method: "DELETE" });

export const validateSource = (source: string, signal?: AbortSignal) =>
  api<SyntaxProblem>("/modules/validate", { method: "POST", body: { source }, signal });

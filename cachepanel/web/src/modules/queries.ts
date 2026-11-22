import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type ModuleSummary = {
  id: number;
  slug: string;
  title: string;
  description: string;
  revision: number;
  updatedAt: string;
  lines: number;
  usedBy: string[];
};

export type ModuleDetail = Omit<ModuleSummary, "lines"> & {
  source: string;
  revisions: { revision: number; createdAt: string }[];
};

export type CatalogCategory = { name: string; title: string };

export type CatalogModule = {
  name: string;
  category: string;
  title: string;
  path: string;
  x86Only: boolean;
  required: boolean;
  automatic: boolean;
  present: boolean;
  usedBy: string[];
};

export type Catalog = { categories: CatalogCategory[]; modules: CatalogModule[] };

export type ModuleDraft = { slug: string; title: string; description: string; source: string };

export const modulesQuery = queryOptions({ queryKey: ["modules"], queryFn: () => api<ModuleSummary[]>("/modules") });

export const moduleQuery = (id: number) =>
  queryOptions({ queryKey: ["module", id], queryFn: () => api<ModuleDetail>(`/modules/${id}`) });

export const catalogQuery = queryOptions({ queryKey: ["catalog"], queryFn: () => api<Catalog>("/catalog") });

export const catalogSourceQuery = (name: string) =>
  queryOptions({
    queryKey: ["catalog-source", name],
    queryFn: () => api<{ source: string; path: string; commit: string }>(`/catalog/${encodeURIComponent(name)}/source`),
  });

export const revisionSource = (id: number, revision: number) =>
  api<{ source: string }>(`/modules/${id}/revisions/${revision}`);

export const createModule = (body: ModuleDraft) => api<{ id: number }>("/modules", { method: "POST", body });

export const saveModule = (id: number, body: ModuleDraft) => api(`/modules/${id}`, { method: "PUT", body });

export const deleteModule = (id: number) => api(`/modules/${id}`, { method: "DELETE" });

export const validateSource = (source: string, signal?: AbortSignal) =>
  api<{ error: string }>("/modules/validate", { method: "POST", body: { source }, signal });

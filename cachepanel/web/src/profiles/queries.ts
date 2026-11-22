import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type Platform = "desktop" | "htpc";
export type CheckState = "pending" | "running" | "passed" | "failed" | "skipped";

export type ProfileSummary = {
  id: number;
  name: string;
  title: string;
  description: string;
  platform: Platform;
  pinnedSha: string | null;
  packageCount: number;
  moduleCount: number;
  candidateTree: string | null;
  candidateRev: string | null;
  publishedTree: string | null;
  publishedRev: string | null;
  publishedAt: string | null;
  checkState: CheckState;
  checkError: string | null;
  checkedAt: string | null;
  updatedAt: string;
};

export type ProfileModule = {
  id: number;
  slug: string;
  title: string;
  description: string;
  required: boolean;
  selected: boolean;
};

export type ProfileDetail = {
  profile: ProfileSummary;
  modules: ProfileModule[];
  packages: string[];
  files: { path: string; content: string }[];
};

export type ProfileSettings = {
  name: string;
  title: string;
  description: string;
  platform: Platform;
  pinnedSha: string | null;
  modules: number[];
  packages: string[];
};

export const platformLabels: Record<Platform, string> = { desktop: "Desktop og laptop", htpc: "HTPC" };

export const profilesQuery = queryOptions({ queryKey: ["profiles"], queryFn: () => api<ProfileSummary[]>("/profiles") });

export const profileQuery = (name: string) =>
  queryOptions({ queryKey: ["profile", name], queryFn: () => api<ProfileDetail>(`/profiles/${name}`) });

export const createProfile = (body: { name: string; title: string; description: string; platform: Platform }) =>
  api<{ name: string }>("/profiles", { method: "POST", body });

export const saveProfile = (name: string, body: ProfileSettings) => api(`/profiles/${name}`, { method: "PUT", body });

export const cloneProfile = (name: string, body: { name: string; title: string }) =>
  api<{ name: string }>(`/profiles/${name}/clone`, { method: "POST", body });

export const deleteProfile = (name: string) => api(`/profiles/${name}`, { method: "DELETE" });

export const profileAction = (name: string, action: "check" | "publish") => api(`/profiles/${name}/${action}`, { method: "POST" });

import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type Platform = "desktop" | "htpc" | "server";
export type CheckState = "pending" | "running" | "passed" | "failed" | "skipped";
export type Branch = "stable" | "testing";

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
  testingTree: string | null;
  testingRev: string | null;
  testingAt: string | null;
  stableTree: string | null;
  stableRev: string | null;
  stableAt: string | null;
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

export const platformLabels: Record<Platform, string> = { desktop: "Desktop and laptop", htpc: "HTPC", server: "Server" };

export const testingAhead = (profile: ProfileSummary) =>
  profile.testingRev !== null && (profile.testingTree !== profile.stableTree || profile.testingRev !== profile.stableRev);

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

export type FileChange = "added" | "removed" | "changed";

export type AwaitingProfile = {
  id: number;
  name: string;
  title: string;
  platform: Platform;
  testingTree: string;
  testingRev: string;
  testingAt: string;
  stableRev: string | null;
  files: { path: string; change: FileChange }[];
};

export type Approval = {
  profiles: AwaitingProfile[];
  commits: { sha: string; subject: string; author: string; committedAt: string }[];
};

export const approvalQuery = queryOptions({ queryKey: ["profiles", "approval"], queryFn: () => api<Approval>("/approval") });

// Ships exactly the reviewed releases.
export const approve = ({ profiles }: Approval) =>
  api("/approval", { method: "POST", body: { profiles: profiles.map(({ id, testingTree, testingRev }) => ({ id, tree: testingTree, rev: testingRev })) } });

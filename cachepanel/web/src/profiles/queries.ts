import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type Platform = "desktop" | "htpc" | "server";
export type CheckState = "pending" | "running" | "passed" | "failed" | "skipped";
export type Branch = "stable" | "testing";
export type SettingKind = "build" | "boot" | "sysctl";

export type KernelSetting = { title: string; description: string; kind: SettingKind; options: string[]; default: string };

export type KernelOffer = { title: string; description: string; settings: Record<string, KernelSetting> };

// Progress arrives once testing has it.
export type ProfileSummary = {
  id: number | null;
  name: string;
  title: string;
  description: string;
  platform: Platform;
  kernel: string;
  kernelSettings: Record<string, string>;
  pinnedSha: string | null;
  modules: string[];
  packages: string[];
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
  testingPaths: number | null;
  testingBytes: number | null;
  stablePaths: number | null;
  stableBytes: number | null;
};

export type ProfileModule = {
  slug: string;
  title: string;
  description: string;
  required: boolean;
  selected: boolean;
};

export type ProfileDetail = {
  profile: ProfileSummary;
  head: string;
  modules: ProfileModule[];
  files: { path: string; content: string }[];
};

// Where a commit starts and why.
export type Change = { base: string; message: string };

export type ProfileSettings = {
  name: string;
  title: string;
  description: string;
  platform: Platform;
  kernel: string;
  kernelSettings: Record<string, string>;
  pinnedSha: string | null;
  modules: string[];
  packages: string[];
};

export const platformLabels: Record<Platform, string> = { desktop: "Desktop and laptop", htpc: "HTPC", server: "Server" };

export const testingAhead = (profile: ProfileSummary) =>
  profile.testingRev !== null && (profile.testingTree !== profile.stableTree || profile.testingRev !== profile.stableRev);

export const profilesQuery = queryOptions({ queryKey: ["profiles"], queryFn: () => api<ProfileSummary[]>("/profiles") });

export const kernelsQuery = queryOptions({ queryKey: ["kernels"], queryFn: () => api<Record<string, KernelOffer>>("/kernels") });

export const profileQuery = (name: string) =>
  queryOptions({ queryKey: ["profile", name], queryFn: () => api<ProfileDetail>(`/profiles/${name}`) });

type Committed = { sha: string; name: string };

export const createProfile = (body: Change & { name: string; title: string; description: string; platform: Platform }) =>
  api<Committed>("/profiles", { method: "POST", body });

export const saveProfile = (name: string, body: Change & ProfileSettings) => api<Committed>(`/profiles/${name}`, { method: "PUT", body });

export const cloneProfile = (name: string, body: Change & { name: string; title: string }) =>
  api<Committed>(`/profiles/${name}/clone`, { method: "POST", body });

export const deleteProfile = (name: string, body: Change) => api<Committed>(`/profiles/${name}`, { method: "DELETE", body });

export const recheckProfile = (name: string) => api(`/profiles/${name}/check`, { method: "POST" });

export type FileChange = "added" | "removed" | "changed";

export type AwaitingProfile = {
  id: number;
  name: string;
  title: string;
  platform: Platform;
  testingTree: string;
  testingRev: string;
  testingAt: string;
  baseRev: string | null;
  files: { path: string; change: FileChange }[];
  paths: number | null;
  bytes: number | null;
};

export type AwaitingDerivation = {
  attr: string;
  version: number;
  name: string;
  builtAt: string | null;
  stableVersion: number | null;
  stableName: string | null;
};

export type StableCheck = { id: number; title: string; state: CheckState; error: string };

export type Approval = {
  profiles: AwaitingProfile[];
  derivations: AwaitingDerivation[];
  commits: { sha: string; subject: string; author: string; committedAt: string }[];
  stable: StableCheck[];
};

export type ApprovalRequest = Pick<Approval, "profiles" | "derivations">;

export const approvalQuery = queryOptions({ queryKey: ["profiles", "approval"], queryFn: () => api<Approval>("/approval") });

// Ships exactly what was reviewed.
export const approve = ({ profiles, derivations }: ApprovalRequest) =>
  api("/approval", {
    method: "POST",
    body: {
      profiles: profiles.map(({ id, testingTree, testingRev }) => ({ id, tree: testingTree, rev: testingRev })),
      derivations: derivations.map(({ attr, version }) => ({ attr, version })),
    },
  });

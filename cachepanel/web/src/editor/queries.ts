import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

// Empty error means valid Nix.
export type SyntaxProblem = { error: string; line?: number; column?: number };

export type OptionDoc = { name: string; type: string; description: string };

// Completions from the newest commit.
export type NixIndex = { options: OptionDoc[]; packages: string[]; lib: string[]; builtins: string[] };

export const nixIndexQuery = queryOptions({
  queryKey: ["editor", "nix"],
  queryFn: () => api<NixIndex>("/editor/nix"),
  staleTime: 10 * 60_000,
});

export const validateSource = (source: string, signal?: AbortSignal) =>
  api<SyntaxProblem>("/modules/validate", { method: "POST", body: { source }, signal });

export const formatSource = (source: string) => api<{ source: string; error: string }>("/editor/format", { method: "POST", body: { source } });

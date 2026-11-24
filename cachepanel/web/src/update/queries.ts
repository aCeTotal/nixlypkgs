import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export type UpdatePhase = "building" | "waiting" | "switching" | "done" | "failed" | "superseded";

export type PanelUpdate = {
  configured: boolean;
  enabled: boolean;
  running: string;
  newest: { rev: string; out: string } | null;
  idle: boolean;
  status: { phase: UpdatePhase; rev: string; target: string; at: string; log: string } | null;
};

export const updateQuery = queryOptions({ queryKey: ["update"], queryFn: () => api<PanelUpdate>("/update") });

export const setAutoUpdate = (enabled: boolean) => api("/update", { method: "PUT", body: { enabled } });

import { CircleCheck, CircleDashed, CircleSlash, CircleX, Hourglass, LoaderCircle } from "lucide-react";
import type { BuildState } from "@/packages/queries";
import { cn } from "@/ui/cn";

export const stateStyles: Record<BuildState, { label: string; icon: typeof CircleCheck; tone: string; dot: string }> = {
  cached: { label: "Cachet", icon: CircleCheck, tone: "bg-success-soft text-success", dot: "bg-success" },
  building: { label: "Bygger", icon: LoaderCircle, tone: "bg-info-soft text-info", dot: "bg-info" },
  queued: { label: "I kø", icon: Hourglass, tone: "bg-warning-soft text-warning-foreground", dot: "bg-warning" },
  failed: { label: "Feilet", icon: CircleX, tone: "bg-danger-soft text-destructive", dot: "bg-destructive" },
  cancelled: { label: "Avbrutt", icon: CircleSlash, tone: "bg-muted text-muted-foreground", dot: "bg-muted-foreground" },
  pending: { label: "Ikke cachet", icon: CircleDashed, tone: "bg-muted text-muted-foreground", dot: "bg-muted-foreground/50" },
};

export function StateBadge({ state, className }: { state: BuildState; className?: string }) {
  const style = stateStyles[state];
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium", style.tone, className)}>
      <style.icon className={cn("size-3.5", state === "building" && "animate-spin")} />
      {style.label}
    </span>
  );
}

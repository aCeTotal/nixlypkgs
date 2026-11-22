import { CircleCheck, CircleDashed, CircleMinus, CircleX, LoaderCircle } from "lucide-react";
import { cn } from "@/ui/cn";
import type { CheckState } from "./queries";

const styles: Record<CheckState, { label: string; icon: typeof CircleCheck; tone: string }> = {
  passed: { label: "Testet og publisert", icon: CircleCheck, tone: "bg-success-soft text-success" },
  running: { label: "Tester", icon: LoaderCircle, tone: "bg-info-soft text-info" },
  pending: { label: "Venter på test", icon: CircleDashed, tone: "bg-warning-soft text-warning-foreground" },
  failed: { label: "Test feilet", icon: CircleX, tone: "bg-danger-soft text-destructive" },
  skipped: { label: "Publisert uten test", icon: CircleMinus, tone: "bg-muted text-muted-foreground" },
};

export function CheckBadge({ state }: { state: CheckState }) {
  const style = styles[state];
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium", style.tone)}>
      <style.icon className={cn("size-3.5", state === "running" && "animate-spin")} />
      {style.label}
    </span>
  );
}

import { CircleCheck, CircleDashed, CircleX, LoaderCircle, Rocket, ScanSearch } from "lucide-react";
import { cn } from "@/ui/cn";
import type { RecipeState } from "./queries";

const styles: Record<RecipeState, { label: string; icon: typeof CircleCheck; tone: string; spin?: boolean }> = {
  importing: { label: "Analyserer", icon: ScanSearch, tone: "bg-info-soft text-info", spin: false },
  draft: { label: "Utkast", icon: CircleDashed, tone: "bg-muted text-muted-foreground" },
  building: { label: "Testbygger", icon: LoaderCircle, tone: "bg-info-soft text-info", spin: true },
  ready: { label: "Klar til publisering", icon: CircleCheck, tone: "bg-success-soft text-success" },
  failed: { label: "Feilet", icon: CircleX, tone: "bg-danger-soft text-destructive" },
  published: { label: "Publisert", icon: Rocket, tone: "bg-primary/10 text-primary" },
};

export function RecipeStateBadge({ state, className }: { state: RecipeState; className?: string }) {
  const style = styles[state];
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium", style.tone, className)}>
      <style.icon className={cn("size-3.5", style.spin && "animate-spin", state === "importing" && "animate-pulse")} />
      {style.label}
    </span>
  );
}

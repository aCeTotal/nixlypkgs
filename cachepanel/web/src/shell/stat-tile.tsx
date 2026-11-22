import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { cn } from "@/ui/cn";

type StatTileProps = {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  icon: LucideIcon;
  tone?: "primary" | "success" | "warning" | "danger" | "info";
};

const tones = {
  primary: "from-primary/20 to-primary/5 text-primary",
  success: "from-success/20 to-success/5 text-success",
  warning: "from-warning/25 to-warning/5 text-warning-foreground",
  danger: "from-destructive/20 to-destructive/5 text-destructive",
  info: "from-info/20 to-info/5 text-info",
};

export function StatTile({ label, value, hint, icon: Icon, tone = "primary" }: StatTileProps) {
  return (
    <div className="relative overflow-hidden rounded-xl border bg-card p-4 shadow-sm">
      <div className={cn("pointer-events-none absolute -top-10 -right-10 size-32 rounded-full bg-gradient-to-br opacity-60 blur-2xl", tones[tone])} />
      <div className="relative flex items-start justify-between gap-3">
        <div className="min-w-0 space-y-1">
          <p className="text-sm text-muted-foreground">{label}</p>
          <p className="text-2xl font-semibold tracking-tight tabular-nums">{value}</p>
          {hint && <p className="truncate text-xs text-muted-foreground">{hint}</p>}
        </div>
        <span className={cn("grid size-10 shrink-0 place-items-center rounded-lg bg-gradient-to-br", tones[tone])}>
          <Icon className="size-5" />
        </span>
      </div>
    </div>
  );
}

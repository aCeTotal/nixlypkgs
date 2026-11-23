import { FlaskConical, ShieldCheck } from "lucide-react";
import type { ReactNode } from "react";
import { cn } from "@/ui/cn";
import type { Branch } from "./queries";

const styles: Record<Branch, { label: string; icon: typeof ShieldCheck; tone: string }> = {
  stable: { label: "Stable", icon: ShieldCheck, tone: "bg-success-soft text-success" },
  testing: { label: "Testing", icon: FlaskConical, tone: "bg-warning-soft text-warning-foreground" },
};

export function BranchBadge({ branch, children }: { branch: Branch; children?: ReactNode }) {
  const style = styles[branch];
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium", style.tone)}>
      <style.icon className="size-3.5" />
      {children ?? style.label}
    </span>
  );
}

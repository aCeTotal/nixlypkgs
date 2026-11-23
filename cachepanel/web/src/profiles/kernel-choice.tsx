import { Gauge, ShieldCheck, type LucideIcon } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import type { Kernel } from "./queries";

const kernels: Record<Kernel, { title: string; icon: LucideIcon; text: string }> = {
  performance: {
    title: "Performance",
    icon: Gauge,
    text: "CachyOS base with BORE, built for each CPU level. Fastest start-up, desktop and games; every controller works out of the box.",
  },
  enterprise: {
    title: "Enterprise",
    icon: ShieldCheck,
    text: "Vanilla, minimal and fully hardened. Module loading locks once the machine has booted; nothing can change the running kernel.",
  },
};

type KernelChoiceProps = { kernel: Kernel; onChange: (kernel: Kernel) => void };

export function KernelChoice({ kernel, onChange }: KernelChoiceProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Kernel</CardTitle>
        <CardDescription>Both enforce signed modules, lockdown and the NixlyOS Secure Boot chain.</CardDescription>
      </CardHeader>
      <CardContent className="grid gap-3 sm:grid-cols-2">
        {(Object.keys(kernels) as Kernel[]).map((value) => {
          const option = kernels[value];
          const chosen = value === kernel;
          return (
            <button
              key={value}
              type="button"
              aria-pressed={chosen}
              onClick={() => onChange(value)}
              className={cn(
                "flex flex-col gap-2 rounded-xl border p-4 text-left transition-all hover:border-primary/50",
                chosen && "border-primary bg-primary/5 ring-2 ring-primary/20",
              )}
            >
              <span className="flex items-center gap-2 font-medium">
                <option.icon className={cn("size-4", chosen ? "text-primary" : "text-muted-foreground")} />
                {option.title}
              </span>
              <span className="text-xs text-muted-foreground">{option.text}</span>
            </button>
          );
        })}
      </CardContent>
    </Card>
  );
}

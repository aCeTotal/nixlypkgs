import { useSuspenseQuery } from "@tanstack/react-query";
import { Cpu, TriangleAlert } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import { KernelSettings } from "./kernel-settings";
import { kernelsQuery } from "./queries";

type KernelChoiceProps = {
  kernel: string;
  settings: Record<string, string>;
  onChange: (kernel: string, settings: Record<string, string>) => void;
};

export function KernelChoice({ kernel, settings, onChange }: KernelChoiceProps) {
  const { data: offers } = useSuspenseQuery(kernelsQuery);
  const offer = offers[kernel];
  return (
    <Card>
      <CardHeader>
        <CardTitle>Kernel</CardTitle>
        <CardDescription>Every kernel enforces signed modules, lockdown and the NixlyOS Secure Boot chain.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        {!offer && (
          <p className="flex items-center gap-2 rounded-lg bg-warning-soft px-3 py-2 text-sm text-warning-foreground">
            <TriangleAlert className="size-4 shrink-0" />
            The source no longer offers {kernel}. Pick another kernel.
          </p>
        )}
        <div className="grid gap-3 sm:grid-cols-3">
          {Object.entries(offers).map(([name, option]) => {
            const chosen = name === kernel;
            return (
              <button
                key={name}
                type="button"
                aria-pressed={chosen}
                onClick={() => onChange(name, chosen ? settings : {})}
                className={cn(
                  "flex flex-col gap-2 rounded-xl border p-4 text-left transition-all hover:border-primary/50",
                  chosen && "border-primary bg-primary/5 ring-2 ring-primary/20",
                )}
              >
                <span className="flex items-center gap-2 font-medium">
                  <Cpu className={cn("size-4", chosen ? "text-primary" : "text-muted-foreground")} />
                  {option.title}
                </span>
                <span className="text-xs text-muted-foreground">{option.description}</span>
              </button>
            );
          })}
        </div>
        {offer && <KernelSettings offer={offer} settings={settings} onChange={(next) => onChange(kernel, next)} />}
      </CardContent>
    </Card>
  );
}

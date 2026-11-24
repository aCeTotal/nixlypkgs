import { Hammer, Power, SlidersHorizontal, type LucideIcon } from "lucide-react";
import { cn } from "@/ui/cn";
import { ToggleGroup, ToggleGroupItem } from "@/ui/toggle-group";
import type { KernelOffer, SettingKind } from "./queries";

const kinds: Record<SettingKind, { label: string; icon: LucideIcon; tone: string }> = {
  build: { label: "Rebuilds the kernel", icon: Hammer, tone: "text-warning-foreground" },
  boot: { label: "Boot option", icon: Power, tone: "text-muted-foreground" },
  sysctl: { label: "Live setting", icon: SlidersHorizontal, tone: "text-muted-foreground" },
};

// Numbers sort as numbers.
const ordered = (options: string[]) =>
  options.every((option) => /^\d+$/.test(option)) ? options.toSorted((a, b) => Number(a) - Number(b)) : options;

const label = (knob: string, option: string) => (knob === "tickRate" ? `${option} Hz` : option);

type KernelSettingsProps = {
  offer: KernelOffer;
  settings: Record<string, string>;
  onChange: (settings: Record<string, string>) => void;
};

export function KernelSettings({ offer, settings, onChange }: KernelSettingsProps) {
  const choose = (knob: string, value: string) => {
    const { [knob]: _, ...rest } = settings;
    onChange(value === offer.settings[knob].default ? rest : { ...rest, [knob]: value });
  };
  return (
    <div className="space-y-1">
      <ul className="divide-y rounded-xl border">
        {Object.entries(offer.settings).map(([knob, setting]) => {
          const value = settings[knob] ?? setting.default;
          const kind = kinds[setting.kind];
          return (
            <li key={knob} className={cn("flex flex-wrap items-center gap-x-6 gap-y-2 p-3", knob in settings && "bg-primary/5")}>
              <div className="min-w-0 flex-1 basis-64">
                <p className="text-sm font-medium">{setting.title}</p>
                <p className="text-xs text-muted-foreground">{setting.description}</p>
                <p className={cn("mt-1 flex items-center gap-1 text-[0.7rem]", kind.tone)}>
                  <kind.icon className="size-3" />
                  {kind.label}
                </p>
              </div>
              <ToggleGroup
                type="single"
                variant="outline"
                size="sm"
                spacing={0}
                value={value}
                onValueChange={(next) => next && choose(knob, next)}
              >
                {ordered(setting.options).map((option) => (
                  <ToggleGroupItem key={option} value={option} className="font-mono text-xs" aria-label={label(knob, option)}>
                    {label(knob, option)}
                    {option === setting.default && <span className="text-[0.6rem] text-muted-foreground">·</span>}
                  </ToggleGroupItem>
                ))}
              </ToggleGroup>
            </li>
          );
        })}
      </ul>
      <p className="px-1 text-xs text-muted-foreground">
        A dot marks the kernel's own value. Changes reach testing first; rebuilding settings compile and sign a kernel for this profile.
      </p>
    </div>
  );
}

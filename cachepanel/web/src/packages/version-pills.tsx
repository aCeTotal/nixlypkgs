import { stateStyles } from "@/builds/state-badge";
import { shortSha } from "@/format/sha";
import { cn } from "@/ui/cn";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/ui/tooltip";
import type { VersionSummary } from "./queries";

// Ring marks the selection.
export function VersionPills({ versions, selected }: { versions: VersionSummary[]; selected: number | null }) {
  return (
    <div className="flex items-center gap-1.5">
      {versions.map((version) => {
        const style = stateStyles[version.state];
        return (
          <Tooltip key={version.id}>
            <TooltipTrigger asChild>
              <span
                className={cn(
                  "h-2.5 w-7 rounded-full",
                  style.dot,
                  version.state === "building" && "animate-pulse",
                  selected === version.id && "ring-2 ring-primary ring-offset-2 ring-offset-card",
                )}
              />
            </TooltipTrigger>
            <TooltipContent>
              {version.name} · {style.label} · {shortSha(version.commit)}
            </TooltipContent>
          </Tooltip>
        );
      })}
    </div>
  );
}

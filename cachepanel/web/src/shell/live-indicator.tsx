import { useConnection } from "@/api/realtime";
import { cn } from "@/ui/cn";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/ui/tooltip";

const labels = { open: "Live", connecting: "Kobler til", closed: "Frakoblet" } as const;
const hints = {
  open: "Sanntidsoppdateringer er aktive",
  connecting: "Kobler til sanntid…",
  closed: "Sanntid frakoblet – prøver igjen",
} as const;
const dots = { open: "bg-success", connecting: "bg-warning", closed: "bg-destructive" } as const;

export function LiveIndicator() {
  const status = useConnection();
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <div className="flex items-center gap-2 rounded-full border bg-card px-3 py-1 text-xs text-muted-foreground">
          <span className="relative flex size-2">
            {status === "open" && <span className="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-60" />}
            <span className={cn("relative inline-flex size-2 rounded-full", dots[status])} />
          </span>
          <span className="max-sm:hidden">{labels[status]}</span>
        </div>
      </TooltipTrigger>
      <TooltipContent>{hints[status]}</TooltipContent>
    </Tooltip>
  );
}

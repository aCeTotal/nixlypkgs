import { Copy } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/ui/button";

export function CommandLine({ command }: { command: string }) {
  const copy = () => void navigator.clipboard.writeText(command).then(() => toast.success("Copied"));
  return (
    <div className="flex items-center gap-2 rounded-lg bg-muted/50 py-1 pr-1 pl-3">
      <code className="min-w-0 flex-1 truncate font-mono text-xs">{command}</code>
      <Button size="icon" variant="ghost" className="size-7 shrink-0" onClick={copy} aria-label="Copy">
        <Copy />
      </Button>
    </div>
  );
}

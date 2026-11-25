import { cn } from "@/ui/cn";
import type { FileDiff } from "./queries";

const statuses: Record<FileDiff["status"], { label: string; tone: string }> = {
  A: { label: "added", tone: "bg-success-soft text-success" },
  M: { label: "changed", tone: "bg-warning-soft text-warning-foreground" },
  D: { label: "deleted", tone: "bg-danger-soft text-destructive" },
  R: { label: "renamed", tone: "bg-primary/10 text-primary" },
  C: { label: "copied", tone: "bg-primary/10 text-primary" },
  T: { label: "type changed", tone: "bg-muted text-muted-foreground" },
};

// Line kinds by first character.
const lineTones: Record<string, string> = {
  "@": "bg-muted/60 text-muted-foreground",
  "+": "bg-success-soft text-success",
  "-": "bg-danger-soft text-destructive",
};

export function DiffView({ file, onPath }: { file: FileDiff; onPath: (path: string) => void }) {
  const status = statuses[file.status];
  const lines = file.patch.replace(/\n$/, "").split("\n").map((text, number) => ({ number, text }));
  return (
    <div className="overflow-hidden rounded-lg border">
      <div className="flex items-center gap-2 border-b bg-muted/40 px-3 py-1.5">
        <span className={cn("rounded px-1.5 py-0.5 text-[0.65rem] font-medium", status.tone)}>{status.label}</span>
        <button type="button" onClick={() => onPath(file.path)} className="min-w-0 truncate font-mono text-xs hover:underline">
          {file.oldPath && `${file.oldPath} → `}
          {file.path}
        </button>
      </div>
      {file.patch ? (
        <pre className="overflow-x-auto py-1 font-mono text-xs leading-relaxed">
          {lines.map((line) => (
            <div key={line.number} className={cn("px-3 whitespace-pre", lineTones[line.text[0]])}>
              {line.text || " "}
            </div>
          ))}
        </pre>
      ) : (
        <p className="px-3 py-2 text-xs text-muted-foreground">No text changes: binary, moved or mode only.</p>
      )}
    </div>
  );
}

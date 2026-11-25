import { useQuery } from "@tanstack/react-query";
import { FileCode, Search } from "lucide-react";
import { useDeferredValue, useEffect, useMemo, useState } from "react";
import { api } from "@/api/http";
import { Dialog, DialogContent, DialogTitle } from "@/ui/dialog";
import { cn } from "@/ui/cn";

const shown = 60;

const filesQuery = { queryKey: ["source", "files"], queryFn: () => api<string[]>("/source/files") };

// Subsequence match, favouring runs and names.
function score(path: string, query: string): number {
  let at = 0;
  let total = 0;
  let run = 0;
  const lower = path.toLowerCase();
  const name = lower.lastIndexOf("/") + 1;
  for (const char of query) {
    const found = lower.indexOf(char, at);
    if (found < 0) return -1;
    run = found === at ? run + 1 : 0;
    total += 1 + run * 2 + (found >= name ? 2 : 0);
    at = found + 1;
  }
  return total - path.length / 100;
}

type QuickOpenProps = { onOpen: (path: string) => void };

// Ctrl+P finds files by letters.
export function QuickOpen({ onOpen }: QuickOpenProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const deferred = useDeferredValue(query.toLowerCase().replaceAll(" ", ""));
  const { data: files = [] } = useQuery({ ...filesQuery, enabled: open });
  const matches = useMemo(() => {
    if (!deferred) return files.slice(0, shown);
    return files
      .map((path) => ({ path, rank: score(path, deferred) }))
      .filter((match) => match.rank >= 0)
      .toSorted((a, b) => b.rank - a.rank)
      .slice(0, shown)
      .map((match) => match.path);
  }, [files, deferred]);

  useEffect(() => {
    const listen = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "p") {
        event.preventDefault();
        setOpen(true);
      }
    };
    window.addEventListener("keydown", listen);
    return () => window.removeEventListener("keydown", listen);
  }, []);

  const choose = (path: string | undefined) => {
    if (!path) return;
    setOpen(false);
    onOpen(path);
  };
  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        setQuery("");
        setActive(0);
      }}
    >
      <DialogContent className="gap-0 overflow-hidden p-0 sm:max-w-2xl">
        <DialogTitle className="sr-only">Go to file</DialogTitle>
        <div className="flex items-center gap-2 border-b px-3">
          <Search className="size-4 text-muted-foreground" />
          <input
            className="h-11 flex-1 bg-transparent font-mono text-sm outline-none"
            placeholder="Go to file…"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setActive(0);
            }}
            onKeyDown={(event) => {
              const moves: Record<string, number> = { ArrowDown: 1, ArrowUp: -1 };
              if (event.key in moves) {
                event.preventDefault();
                setActive((current) => Math.min(Math.max(current + moves[event.key], 0), matches.length - 1));
              }
              if (event.key === "Enter") choose(matches[active]);
            }}
          />
        </div>
        <ul className="max-h-[60vh] overflow-y-auto p-1">
          {matches.map((path, index) => (
            <li key={path}>
              <button
                type="button"
                onMouseEnter={() => setActive(index)}
                onClick={() => choose(path)}
                className={cn("flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left", index === active && "bg-primary/10 text-primary")}
              >
                <FileCode className="size-3.5 shrink-0 opacity-70" />
                <span className="truncate font-mono text-xs font-medium">{path.slice(path.lastIndexOf("/") + 1)}</span>
                <span className="truncate font-mono text-[0.7rem] text-muted-foreground">{path}</span>
              </button>
            </li>
          ))}
          {matches.length === 0 && <li className="px-3 py-6 text-center text-sm text-muted-foreground">No file matches.</li>}
        </ul>
      </DialogContent>
    </Dialog>
  );
}

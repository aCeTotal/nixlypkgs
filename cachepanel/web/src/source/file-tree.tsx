import { useQuery } from "@tanstack/react-query";
import { ChevronRight, FileCode, Folder } from "lucide-react";
import { useState } from "react";
import { cn } from "@/ui/cn";
import { Skeleton } from "@/ui/skeleton";
import { treeQuery, type Entry } from "./queries";

type TreeProps = { selected: string; onSelect: (path: string) => void };

const indent = (depth: number) => ({ paddingLeft: `${0.5 + depth * 0.875}rem` });

export function FileTree(props: TreeProps) {
  return <FolderContents path="" depth={0} {...props} />;
}

function FolderContents({ path, depth, selected, onSelect }: TreeProps & { path: string; depth: number }) {
  const { data } = useQuery(treeQuery(path));
  if (!data) {
    return <Skeleton className="mx-2 my-1 h-5" style={indent(depth)} />;
  }
  return (
    <ul>
      {data.entries.map((entry) =>
        entry.dir ? (
          <FolderRow key={entry.path} entry={entry} depth={depth} selected={selected} onSelect={onSelect} />
        ) : (
          <li key={entry.path}>
            <button
              type="button"
              onClick={() => onSelect(entry.path)}
              style={indent(depth)}
              className={cn(
                "flex w-full items-center gap-1.5 rounded-md py-1 pr-2 text-left font-mono text-xs hover:bg-muted",
                entry.path === selected && "bg-primary/10 text-primary",
              )}
            >
              <FileCode className="ml-4 size-3.5 shrink-0 opacity-70" />
              <span className="truncate">{entry.name}</span>
            </button>
          </li>
        ),
      )}
    </ul>
  );
}

function FolderRow({ entry, depth, selected, onSelect }: TreeProps & { entry: Entry; depth: number }) {
  const [open, setOpen] = useState(selected.startsWith(`${entry.path}/`));
  return (
    <li>
      <button
        type="button"
        onClick={() => setOpen(!open)}
        style={indent(depth)}
        className="flex w-full items-center gap-1.5 rounded-md py-1 pr-2 text-left text-xs hover:bg-muted"
      >
        <ChevronRight className={cn("size-3.5 shrink-0 text-muted-foreground transition-transform", open && "rotate-90")} />
        <Folder className="size-3.5 shrink-0 text-primary/80" />
        <span className="truncate">{entry.name}</span>
      </button>
      {open && <FolderContents path={entry.path} depth={depth + 1} selected={selected} onSelect={onSelect} />}
    </li>
  );
}

import { Blocks, ChevronRight, CornerDownRight, Dot, Search, SquareFunction, type LucideIcon } from "lucide-react";
import { memo, useState } from "react";
import { cn } from "@/ui/cn";
import { Input } from "@/ui/input";
import type { OutlineItem, OutlineKind } from "./outline";

const icons: Record<OutlineKind, LucideIcon> = {
  section: Blocks,
  helper: SquareFunction,
  setting: Dot,
  import: CornerDownRight,
};

const tones: Record<OutlineKind, string> = {
  section: "font-medium text-foreground",
  helper: "text-chart-5",
  setting: "text-muted-foreground",
  import: "text-chart-1",
};

type OutlineProps = {
  items: OutlineItem[];
  active: string[];
  onSelect: (item: OutlineItem) => void;
};

// Items matching the filter, with their ancestors.
function filtered(items: OutlineItem[], query: string): OutlineItem[] {
  return items.flatMap((item) => {
    const children = filtered(item.children, query);
    return item.label.toLowerCase().includes(query) || children.length > 0 ? [{ ...item, children }] : [];
  });
}

export function ModuleOutline({ items, active, onSelect }: OutlineProps) {
  const [query, setQuery] = useState("");
  const [toggled, setToggled] = useState<Record<string, boolean>>({});
  const needle = query.trim().toLowerCase();
  const shown = needle ? filtered(items, needle) : items;
  const toggle = (key: string, open: boolean) => setToggled((current) => ({ ...current, [key]: !open }));
  return (
    <div className="flex h-full min-h-0 flex-col gap-2">
      <div className="relative">
        <Search className="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground" />
        <Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Find in module" className="h-8 pl-8 text-sm" />
      </div>
      <nav className="min-h-0 flex-1 overflow-y-auto pr-1" aria-label="Disposisjon">
        {shown.length === 0 && <p className="px-2 py-4 text-sm text-muted-foreground">No matches.</p>}
        <Branch items={shown} depth={0} active={active} expandAll={needle !== ""} toggled={toggled} onToggle={toggle} onSelect={onSelect} />
      </nav>
    </div>
  );
}

type BranchProps = {
  items: OutlineItem[];
  depth: number;
  active: string[];
  expandAll: boolean;
  toggled: Record<string, boolean>;
  onToggle: (key: string, open: boolean) => void;
  onSelect: (item: OutlineItem) => void;
};

const Branch = memo(function Branch({ items, depth, active, expandAll, toggled, onToggle, onSelect }: BranchProps) {
  return (
    <ul className={cn(depth > 0 && "ml-3 border-l border-border/60 pl-1")}>
      {items.map((item) => {
        const Icon = icons[item.kind];
        const onPath = active.includes(item.key);
        const current = active.at(-1) === item.key;
        // Sections and the cursor path start open.
        const open = expandAll || (toggled[item.key] ?? (item.kind === "section" || onPath));
        return (
          <li key={item.key}>
            <div
              className={cn(
                "group flex items-center gap-1 rounded-md pr-1.5 text-[0.8rem] hover:bg-muted",
                current && "bg-primary/10 text-primary hover:bg-primary/15",
              )}
            >
              <button
                type="button"
                aria-label={open ? "Collapse" : "Expand"}
                onClick={() => onToggle(item.key, open)}
                className={cn("grid size-5 shrink-0 place-items-center rounded text-muted-foreground", item.children.length === 0 && "invisible")}
              >
                <ChevronRight className={cn("size-3 transition-transform", open && "rotate-90")} />
              </button>
              <button type="button" onClick={() => onSelect(item)} className="flex min-w-0 flex-1 items-center gap-1.5 py-1 text-left">
                <Icon className={cn("size-3.5 shrink-0", tones[item.kind], current && "text-primary")} />
                <span title={item.label} className={cn("truncate font-mono", tones[item.kind], current && "text-primary")}>
                  {item.label}
                </span>
                <span className="ml-auto shrink-0 pl-2 text-[0.7rem] text-muted-foreground/70 tabular-nums">{item.line}</span>
              </button>
            </div>
            {open && item.children.length > 0 && (
              <Branch
                items={item.children}
                depth={depth + 1}
                active={active}
                expandAll={expandAll}
                toggled={toggled}
                onToggle={onToggle}
                onSelect={onSelect}
              />
            )}
          </li>
        );
      })}
    </ul>
  );
});

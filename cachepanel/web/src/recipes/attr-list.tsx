import { X } from "lucide-react";
import { AttrSearch } from "@/nixpkgs/attr-search";
import { Button } from "@/ui/button";

type AttrListProps = { title: string; hint: string; attrs: string[]; onChange: (attrs: string[]) => void };

// Searchable nixpkgs attribute list.
export function AttrList({ title, hint, attrs, onChange }: AttrListProps) {
  return (
    <div className="space-y-3 rounded-xl border p-4">
      <div>
        <h3 className="font-medium">{title}</h3>
        <p className="text-sm text-muted-foreground">{hint}</p>
      </div>
      <AttrSearch label={`Add to ${title.toLowerCase()}`} placeholder="Search nixpkgs" exclude={attrs} onPick={(attr) => onChange([...attrs, attr])} />
      {attrs.length > 0 && (
        <ul className="flex flex-wrap gap-2">
          {attrs.map((attr) => (
            <li key={attr} className="flex items-center gap-1 rounded-lg border bg-muted/40 py-0.5 pr-0.5 pl-2.5 font-mono text-xs">
              {attr}
              <Button variant="ghost" size="icon-sm" aria-label={`Remove ${attr}`} onClick={() => onChange(attrs.filter((other) => other !== attr))}>
                <X />
              </Button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

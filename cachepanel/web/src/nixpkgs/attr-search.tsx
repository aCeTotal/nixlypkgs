import { useQuery } from "@tanstack/react-query";
import { Plus, Search } from "lucide-react";
import { useId, useState, type FormEvent } from "react";
import { useDebounced } from "@/shell/use-debounced";
import { Button } from "@/ui/button";
import { Input } from "@/ui/input";
import { attrPattern, minQuery, searchQuery } from "./queries";

const debounceMs = 200;

type AttrSearchProps = {
  label: string;
  placeholder: string;
  exclude: string[];
  onPick: (attr: string) => void;
};

// Stable nixpkgs search, free entry.
export function AttrSearch({ label, placeholder, exclude, onPick }: AttrSearchProps) {
  const listId = useId();
  const [text, setText] = useState("");
  const query = useDebounced(text.trim(), debounceMs);
  const { data = [] } = useQuery(searchQuery(query));
  const suggestions = query.length >= minQuery ? data.filter((attr) => !exclude.includes(attr)) : [];
  const typed = text.trim();
  const valid = attrPattern.test(typed) && !exclude.includes(typed);
  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (!valid) return;
    onPick(typed);
    setText("");
  };
  return (
    <form onSubmit={submit} className="flex gap-2">
      <div className="relative flex-1">
        <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          list={listId}
          aria-label={label}
          aria-invalid={typed !== "" && !attrPattern.test(typed)}
          className="pl-8 font-mono"
          placeholder={placeholder}
          value={text}
          onChange={(event) => setText(event.target.value)}
        />
        <datalist id={listId}>
          {suggestions.map((attr) => (
            <option key={attr} value={attr}>
              {attr}
            </option>
          ))}
        </datalist>
      </div>
      <Button type="submit" variant="outline" disabled={!valid}>
        <Plus />
        Add
      </Button>
    </form>
  );
}

import { snippetCompletion, type Completion, type CompletionContext, type CompletionResult } from "@codemirror/autocomplete";
import { atBinding, enclosingPath, withinPkgs } from "./nix-context";
import { hasPrefix, prefixRange, type PreparedIndex } from "./nix-index";

const keywords = ["if", "then", "else", "let", "in", "with", "inherit", "rec", "assert", "import", "true", "false", "null"];

// Builtins callable without the builtins prefix.
const globals = ["abort", "baseNameOf", "derivation", "dirOf", "fetchGit", "fetchTarball", "fetchTree", "fromTOML", "isNull", "map", "placeholder", "removeAttrs", "throw", "toString"];

const snippets = [
  snippetCompletion("{ config, lib, pkgs, ... }:\n\n{\n\t${}\n}", { label: "module", detail: "NixOS module", type: "keyword" }),
  snippetCompletion("lib.mkIf ${condition} {\n\t${}\n}", { label: "mkIf", detail: "conditional config", type: "function" }),
  snippetCompletion("lib.mkEnableOption \"${description}\"", { label: "mkEnableOption", detail: "boolean option", type: "function" }),
  snippetCompletion(
    "lib.mkOption {\n\ttype = lib.types.${str};\n\tdefault = ${value};\n\tdescription = \"${}\";\n}",
    { label: "mkOption", detail: "new option", type: "function" },
  ),
  snippetCompletion("let\n\t${name} = ${value};\nin\n${}", { label: "let", detail: "let … in", type: "keyword" }),
  snippetCompletion("if ${condition} then ${yes} else ${no}", { label: "if", detail: "if … then … else", type: "keyword" }),
];

const limit = 300;

function fromSorted(sorted: string[], prefix: string, type: string): Completion[] {
  const [from, to] = prefixRange(sorted, prefix);
  return sorted.slice(from, Math.min(to, from + limit)).map((label) => ({ label, type }));
}

function optionInfo(name: string, type: string, description: string) {
  return () => {
    const box = document.createElement("div");
    box.className = "cm-option-info";
    const head = box.appendChild(document.createElement("div"));
    head.className = "cm-option-name";
    head.textContent = name;
    const kind = box.appendChild(document.createElement("div"));
    kind.className = "cm-option-type";
    kind.textContent = type;
    box.appendChild(document.createElement("p")).textContent = description;
    return box;
  };
}

// Free names match <name>.
function resolve(index: PreparedIndex, segments: string[]): string | null {
  let path = "";
  for (const segment of segments) {
    const direct = path ? `${path}.${segment}` : segment;
    if (hasPrefix(index.optionNames, direct + ".") || hasPrefix(index.optionNames, direct)) {
      path = direct;
      continue;
    }
    const named = `${path}.<name>`;
    if (!path || !hasPrefix(index.optionNames, named)) return null;
    path = named;
  }
  return path;
}

// Next option segments under base.
function optionCompletions(index: PreparedIndex, base: string, partial: string): Completion[] {
  const prefix = (base ? base + "." : "") + partial;
  const [from, to] = prefixRange(index.optionNames, prefix);
  const seen = new Map<string, Completion>();
  const start = base ? base.length + 1 : 0;
  for (let i = from; i < to && seen.size < limit; i++) {
    const option = index.options[i];
    const rest = option.name.slice(start);
    const dot = rest.indexOf(".");
    const segment = dot < 0 ? rest : rest.slice(0, dot);
    if (seen.has(segment)) continue;
    seen.set(
      segment,
      dot < 0
        ? { label: segment, type: "property", detail: option.type, info: optionInfo(option.name, option.type, option.description), boost: 1 }
        : { label: segment, type: "namespace", detail: "…" },
    );
  }
  return [...seen.values()];
}

// Options, packages, lib or builtins.
export function nixCompletion(index: () => PreparedIndex | undefined) {
  return (context: CompletionContext): CompletionResult | null => {
    const word = context.matchBefore(/[A-Za-z_<][\w'<>-]*(\.[A-Za-z_<][\w'<>-]*)*\.?/);
    if (!word || (word.from === word.to && !context.explicit)) return null;
    const prepared = index();
    const text = word.text;
    const dot = text.lastIndexOf(".");
    const head = dot < 0 ? "" : text.slice(0, dot);
    const partial = text.slice(dot + 1);
    const from = word.from + dot + 1;
    const root = text.split(".")[0];
    const libraries: Record<string, string[] | undefined> = { pkgs: prepared?.packages, lib: prepared?.lib, builtins: prepared?.builtins };
    const library = dot > 0 ? libraries[root] : undefined;
    if (library) {
      return { from: word.from + root.length + 1, options: fromSorted(library, text.slice(root.length + 1), root === "pkgs" ? "class" : "function"), validFor: /^[\w'.-]*$/ };
    }
    const binding = atBinding(context.state, word.from);
    const inConfig = root === "config" && dot > 0;
    if (prepared && (binding || inConfig)) {
      const outer = binding ? enclosingPath(context.state, word.from) : [];
      const typed = (inConfig ? text.split(".").slice(1, -1) : head ? head.split(".") : []);
      const base = resolve(prepared, [...outer, ...typed]);
      if (base !== null) return { from, options: optionCompletions(prepared, base, partial), validFor: /^[\w'<>-]*$/ };
    }
    if (dot >= 0) return null;
    const names: Completion[] = [
      ...keywords.map((label) => ({ label, type: "keyword" })),
      ...globals.map((label) => ({ label, type: "function" })),
      ...snippets,
      ...(prepared && withinPkgs(context.state, word.from) ? fromSorted(prepared.packages, partial, "class") : []),
    ];
    return { from: word.from, options: names, validFor: /^[\w'-]*$/ };
  };
}

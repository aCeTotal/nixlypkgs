import { nixParser as parser } from "@/editor/nix/language";

type Node = ReturnType<typeof parser.parse>["topNode"];

export type OutlineKind = "section" | "helper" | "setting" | "import";

export type OutlineItem = {
  key: string;
  label: string;
  kind: OutlineKind;
  from: number;
  to: number;
  line: number;
  children: OutlineItem[];
};

const containers = new Set(["AttrSet", "RecAttrSet", "LetAttrSet"]);

// Skips wrappers down to the structural expression.
function unwrap(node: Node): Node {
  switch (node.name) {
    case "Function":
    case "With":
    case "Assert":
    case "App":
      return node.lastChild ? unwrap(node.lastChild) : node;
    case "Parenthesized":
      return node.firstChild?.nextSibling ? unwrap(node.firstChild.nextSibling) : node;
    default:
      return node;
  }
}

function children(node: Node): Node[] {
  const found: Node[] = [];
  for (let child = node.firstChild; child; child = child.nextSibling) found.push(child);
  return found;
}

class Builder {
  private readonly source: string;
  private readonly lineStarts: number[] = [0];

  constructor(source: string) {
    this.source = source;
    for (let i = 0; i < source.length; i++) if (source[i] === "\n") this.lineStarts.push(i + 1);
  }

  private line(pos: number) {
    let low = 0;
    let high = this.lineStarts.length - 1;
    while (low < high) {
      const mid = (low + high + 1) >> 1;
      if (this.lineStarts[mid] <= pos) low = mid;
      else high = mid - 1;
    }
    return low + 1;
  }

  private text(node: Node) {
    return this.source.slice(node.from, node.to);
  }

  private item(label: string, kind: OutlineKind, node: Node, nested: OutlineItem[]): OutlineItem {
    return { key: `${node.from}`, label, kind, from: node.from, to: node.to, line: this.line(node.from), children: nested };
  }

  // Items a value expression contributes.
  of(node: Node, letKind: OutlineKind = "helper"): OutlineItem[] {
    const value = unwrap(node);
    if (value.name === "Let") return this.let(value, letKind);
    if (containers.has(value.name)) return this.binds(value, "setting");
    if (value.name === "List") return children(value).flatMap((element) => this.element(element));
    if (value.name === "BinaryExpr") return children(value).flatMap((operand) => this.of(operand));
    return [];
  }

  // Top-level bindings the body uses are sections.
  private let(node: Node, kind: OutlineKind): OutlineItem[] {
    const parts = children(node);
    const body = parts.at(-1);
    const bound = this.binds(node, kind);
    if (!body || body.name === "Bind") return bound;
    if (kind === "section") {
      const used = new Set(this.text(body).match(/[A-Za-z_][\w'-]*/g));
      for (const item of bound) if (!used.has(item.label)) item.kind = "helper";
    }
    return [...bound, ...this.of(body)];
  }

  private binds(node: Node, kind: OutlineKind): OutlineItem[] {
    return children(node)
      .filter((part) => part.name === "Bind")
      .map((bind) => this.bind(bind, kind));
  }

  private bind(node: Node, kind: OutlineKind): OutlineItem {
    const parts = children(node);
    const path = parts.find((part) => part.name === "AttrPath");
    if (!path) return this.item(this.text(node).replace(/\s+/g, " ").replace(/;$/, ""), "setting", node, []);
    return this.item(this.text(path).replace(/"/g, ""), kind, node, this.of(parts.at(-1)!));
  }

  // mkMerge members merge in, names import.
  private element(node: Node): OutlineItem[] {
    const value = unwrap(node);
    if (value.name === "Identifier") return [this.item(this.text(value), "import", value, [])];
    if (containers.has(value.name)) return this.binds(value, "setting");
    return [];
  }
}

// Sections, helpers and settings of a module.
export function outline(source: string): OutlineItem[] {
  const top = parser.parse(source).topNode;
  return new Builder(source).of(top.firstChild ?? top, "section");
}

// Keys from the root to the item under the cursor.
export function activePath(items: OutlineItem[], pos: number): string[] {
  for (const item of items) {
    if (pos < item.from || pos > item.to) continue;
    return [item.key, ...activePath(item.children, pos)];
  }
  return [];
}

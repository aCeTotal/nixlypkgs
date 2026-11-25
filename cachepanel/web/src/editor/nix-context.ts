import { syntaxTree } from "@codemirror/language";
import type { EditorState } from "@codemirror/state";
import type { SyntaxNode } from "@lezer/common";

// Placeholders for user-chosen names.
const placeholder = "<name>";

function pathOf(attrPath: SyntaxNode, state: EditorState): string[] {
  const segments: string[] = [];
  for (let child = attrPath.firstChild; child; child = child.nextSibling) {
    if (child.name === "Identifier") segments.push(state.sliceDoc(child.from, child.to));
    if (child.name === "String" || child.name === "Interpolation") segments.push(placeholder);
  }
  return segments;
}

// Option path around pos.
export function enclosingPath(state: EditorState, pos: number): string[] {
  const path: string[] = [];
  for (let node: SyntaxNode | null = syntaxTree(state).resolveInner(pos, -1); node; node = node.parent) {
    if (node.name !== "Bind") continue;
    const attrPath = node.getChild("AttrPath");
    if (!attrPath || attrPath.to >= pos) continue;
    path.unshift(...pathOf(attrPath, state));
    const owner = node.parent?.name;
    if (owner === "Let" || owner === "LetAttrSet") break;
  }
  return path[0] === "config" ? path.slice(1) : path;
}

// with pkgs makes names packages.
export function withinPkgs(state: EditorState, pos: number): boolean {
  for (let node: SyntaxNode | null = syntaxTree(state).resolveInner(pos, -1); node; node = node.parent) {
    const scope = node.name === "With" ? node.firstChild?.nextSibling : null;
    if (scope && state.sliceDoc(scope.from, scope.to) === "pkgs") return true;
  }
  return false;
}

// Bindings start after { or ;.
export function atBinding(state: EditorState, from: number): boolean {
  const before = state.sliceDoc(Math.max(0, from - 200), from).replace(/#[^\n]*\n/g, "\n").trimEnd();
  return before.endsWith("{") || before.endsWith(";");
}

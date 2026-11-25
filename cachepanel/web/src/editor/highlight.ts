import { HighlightStyle } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";

// One palette for every language.
export const highlight = HighlightStyle.define([
  { tag: [t.keyword, t.controlKeyword, t.moduleKeyword, t.operatorKeyword, t.definitionKeyword], color: "var(--chart-5)", fontWeight: "500" },
  { tag: [t.string, t.special(t.string), t.character, t.docString], color: "var(--chart-3)" },
  { tag: [t.regexp, t.escape], color: "var(--pink)" },
  { tag: [t.number, t.bool, t.null, t.atom, t.unit], color: "var(--chart-2)" },
  { tag: [t.lineComment, t.blockComment, t.docComment, t.comment], color: "var(--muted-foreground)", fontStyle: "italic" },
  { tag: [t.propertyName, t.attributeName], color: "var(--chart-1)" },
  { tag: [t.function(t.variableName), t.function(t.propertyName), t.macroName], color: "var(--info)" },
  { tag: [t.definition(t.variableName), t.definition(t.propertyName)], color: "var(--chart-1)", fontWeight: "500" },
  { tag: [t.typeName, t.className, t.namespace, t.tagName], color: "var(--chart-4)" },
  { tag: [t.url, t.link, t.literal], color: "var(--chart-4)", textDecoration: "underline" },
  { tag: [t.self, t.special(t.variableName)], color: "var(--chart-5)", fontStyle: "italic" },
  { tag: [t.operator, t.derefOperator, t.compareOperator, t.arithmeticOperator, t.logicOperator], color: "var(--chart-2)" },
  { tag: [t.brace, t.squareBracket, t.paren, t.angleBracket, t.separator, t.punctuation], color: "var(--muted-foreground)" },
  { tag: [t.meta, t.annotation, t.processingInstruction], color: "var(--warning-foreground)" },
  { tag: t.heading, color: "var(--primary)", fontWeight: "700" },
  { tag: t.strong, fontWeight: "700" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
  { tag: t.inserted, color: "var(--success)" },
  { tag: t.deleted, color: "var(--destructive)" },
  { tag: t.changed, color: "var(--warning-foreground)" },
  { tag: t.invalid, color: "var(--destructive)", textDecoration: "underline wavy" },
]);

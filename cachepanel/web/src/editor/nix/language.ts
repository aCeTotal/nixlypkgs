import {
  continuedIndent,
  delimitedIndent,
  foldInside,
  foldNodeProp,
  indentNodeProp,
  LanguageSupport,
  LRLanguage,
} from "@codemirror/language";
import { styleTags, tags as t } from "@lezer/highlight";
import { parser } from "./nix.grammar";

export const nixParser = parser.configure({
  props: [
    indentNodeProp.add({
      Parenthesized: delimitedIndent({ closing: ")" }),
      AttrSet: delimitedIndent({ closing: "}" }),
      List: delimitedIndent({ closing: "]" }),
      Let: continuedIndent({ except: /^\s*in\b/ }),
    }),
    foldNodeProp.add({
      AttrSet: foldInside,
      List: foldInside,
      IndentedString: foldInside,
      Let(node) {
        const first = node.getChild("let");
        const last = node.getChild("in");
        return first && last ? { from: first.to, to: last.from } : null;
      },
    }),
    styleTags({
      Identifier: t.variableName,
      "Bind/AttrPath/Identifier": t.definition(t.propertyName),
      "Select/AttrPath/Identifier": t.propertyName,
      Boolean: t.bool,
      String: t.string,
      IndentedString: t.string,
      LineComment: t.lineComment,
      BlockComment: t.blockComment,
      Float: t.float,
      Integer: t.integer,
      Null: t.null,
      URI: t.url,
      "SPath Path HPath": t.literal,
      "( )": t.paren,
      "{ }": t.brace,
      "[ ]": t.squareBracket,
      "if then else": t.controlKeyword,
      "import with let in rec builtins inherit assert or": t.keyword,
    }),
  ],
});

const nixLanguage = LRLanguage.define({
  name: "nix",
  parser: nixParser,
  languageData: {
    commentTokens: { line: "#", block: { open: "/*", close: "*/" } },
    indentOnInput: /^\s*(in|\}|\)|\])$/,
  },
});

export function nix() {
  return new LanguageSupport(nixLanguage);
}

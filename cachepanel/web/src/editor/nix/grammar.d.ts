declare module "*.grammar" {
  import type { LRParser } from "@lezer/lr";

  export const parser: LRParser;
}

declare module "*.grammar.terms" {
  export const strContent: number;
  export const strDollarBrace: number;
  export const strEnd: number;
  export const escapeSequence: number;
  export const indStrContent: number;
  export const indStrDollarBrace: number;
  export const indStrEnd: number;
  export const indEscapeSequence: number;
}

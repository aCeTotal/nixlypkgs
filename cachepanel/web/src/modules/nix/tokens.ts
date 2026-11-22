import { ExternalTokenizer, type InputStream } from "@lezer/lr";
import {
  escapeSequence,
  indEscapeSequence,
  indStrContent,
  indStrDollarBrace,
  indStrEnd,
  strContent,
  strDollarBrace,
  strEnd,
} from "./nix.grammar.terms";

const quote = 34;
const dollar = 36;
const apostrophe = 39;
const backslash = 92;
const braceL = 123;

// "...": backslash escapes, ${ interpolates.
export const string = new ExternalTokenizer((input) => {
  for (let length = 0; ; length++) {
    const next = input.next;
    const interpolates = next === dollar && input.peek(1) === braceL;
    if (next < 0 || next === quote || next === backslash || interpolates) {
      if (length > 0) input.acceptToken(strContent);
      else if (next === quote) input.acceptToken(strEnd, 1);
      else if (interpolates) input.acceptToken(strDollarBrace, 2);
      else if (next === backslash) input.acceptToken(escapeSequence, input.peek(1) < 0 ? 1 : 2);
      return;
    }
    if (next === dollar && input.peek(1) === dollar) input.advance();
    input.advance();
  }
});

// ''...'': ''$ ''' and ''\ escape, ${ interpolates.
export const indentedString = new ExternalTokenizer((input) => {
  for (let length = 0; ; length++) {
    const next = input.next;
    const quotes = next === apostrophe && input.peek(1) === apostrophe;
    const interpolates = next === dollar && input.peek(1) === braceL;
    if (next < 0 || quotes || interpolates) {
      if (length > 0) input.acceptToken(indStrContent);
      else if (interpolates) input.acceptToken(indStrDollarBrace, 2);
      else if (quotes) acceptQuotes(input);
      return;
    }
    if (next === dollar && input.peek(1) === dollar) input.advance();
    input.advance();
  }
});

function acceptQuotes(input: InputStream) {
  const after = input.peek(2);
  if (after === dollar || after === apostrophe) input.acceptToken(indEscapeSequence, 3);
  else if (after === backslash) input.acceptToken(indEscapeSequence, input.peek(3) < 0 ? 3 : 4);
  else input.acceptToken(indStrEnd, 2);
}

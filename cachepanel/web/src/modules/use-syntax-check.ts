import { useEffect, useState } from "react";
import { validateSource } from "./queries";

const delay = 500;

export type SyntaxState = { checking: boolean; error: string };

// Debounced server-side parse.
export function useSyntaxCheck(source: string) {
  const [state, setState] = useState<SyntaxState>({ checking: false, error: "" });
  useEffect(() => {
    const abort = new AbortController();
    const timer = window.setTimeout(() => {
      setState((current) => ({ ...current, checking: true }));
      validateSource(source, abort.signal)
        .then(({ error }) => setState({ checking: false, error }))
        .catch(() => setState((current) => ({ ...current, checking: false })));
    }, delay);
    return () => {
      window.clearTimeout(timer);
      abort.abort();
    };
  }, [source]);
  return state;
}

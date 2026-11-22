import { useEffect, useState } from "react";
import { validateSource, type SyntaxProblem } from "./queries";

const delay = 500;

export type SyntaxState = { checking: boolean; problem: SyntaxProblem };

// Debounced server-side parse.
export function useSyntaxCheck(source: string) {
  const [state, setState] = useState<SyntaxState>({ checking: false, problem: { error: "" } });
  useEffect(() => {
    const abort = new AbortController();
    const timer = window.setTimeout(() => {
      setState((current) => ({ ...current, checking: true }));
      validateSource(source, abort.signal)
        .then((problem) => setState({ checking: false, problem }))
        .catch(() => setState((current) => ({ ...current, checking: false })));
    }, delay);
    return () => {
      window.clearTimeout(timer);
      abort.abort();
    };
  }, [source]);
  return state;
}

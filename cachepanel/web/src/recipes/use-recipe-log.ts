import { useEffect, useState } from "react";
import { recipeLog } from "./queries";

const pollMs = 1000;
const keepChars = 400_000;
const chunkChars = 256 * 1024;

// Tails the log per build.
export function useRecipeLog(id: number, live: boolean) {
  const [text, setText] = useState("");
  useEffect(() => {
    let stopped = false;
    let busy = false;
    let next = 0;
    let collected = "";
    // Full chunks mean more is waiting.
    const pull = async (): Promise<void> => {
      const chunk = await recipeLog(id, next);
      if (stopped || chunk.text === "") return;
      collected = (collected + chunk.text).slice(-keepChars);
      next = chunk.next;
      setText(collected);
      if (chunk.text.length >= chunkChars) return pull();
    };
    const poll = () => {
      if (busy) return;
      busy = true;
      void pull().finally(() => {
        busy = false;
      });
    };
    poll();
    const timer = live ? window.setInterval(poll, pollMs) : undefined;
    return () => {
      stopped = true;
      window.clearInterval(timer);
    };
  }, [id, live]);
  return text;
}

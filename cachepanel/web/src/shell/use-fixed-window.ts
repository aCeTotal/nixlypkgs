import { useEffectEvent, useLayoutEffect, useReducer, type RefObject } from "react";

type Range = { first: number; last: number };

const emptyRange: Range = { first: 0, last: -1 };

// Equal ranges skip rendering.
function settle(current: Range, next: Range) {
  return current.first === next.first && current.last === next.last ? current : next;
}

function rangeIn(element: HTMLElement | null, count: number, rowHeight: number, overscan: number): Range {
  if (!element || count === 0) return emptyRange;
  const top = element.scrollTop;
  return {
    first: Math.max(0, Math.floor(top / rowHeight) - overscan),
    last: Math.min(count - 1, Math.ceil((top + element.clientHeight) / rowHeight) + overscan),
  };
}

// Rows of one height, in O(1).
export function useFixedWindow(scrollRef: RefObject<HTMLElement | null>, count: number, rowHeight: number, overscan: number) {
  const [range, measured] = useReducer(settle, emptyRange);
  const onViewportChange = useEffectEvent(() => measured(rangeIn(scrollRef.current, count, rowHeight, overscan)));

  useLayoutEffect(() => {
    const element = scrollRef.current;
    if (!element) return;
    const onChange = () => onViewportChange();
    element.addEventListener("scroll", onChange, { passive: true });
    const observer = new ResizeObserver(onChange);
    observer.observe(element);
    return () => {
      element.removeEventListener("scroll", onChange);
      observer.disconnect();
    };
  }, [scrollRef]);

  useLayoutEffect(() => measured(rangeIn(scrollRef.current, count, rowHeight, overscan)), [scrollRef, count, rowHeight, overscan]);

  return { first: range.first, last: Math.min(range.last, count - 1), totalSize: count * rowHeight };
}

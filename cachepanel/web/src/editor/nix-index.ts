import type { NixIndex, OptionDoc } from "./queries";

// Sorted once, binary-searched by prefix.
export type PreparedIndex = {
  options: OptionDoc[];
  optionNames: string[];
  packages: string[];
  lib: string[];
  builtins: string[];
};

const byName = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

export function prepare(index: NixIndex): PreparedIndex {
  const options = index.options.toSorted((a, b) => byName(a.name, b.name));
  return {
    options,
    optionNames: options.map((option) => option.name),
    packages: index.packages.toSorted(byName),
    lib: index.lib.toSorted(byName),
    builtins: index.builtins.toSorted(byName),
  };
}

function lowerBound(sorted: string[], value: string) {
  let low = 0;
  let high = sorted.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (sorted[middle] < value) low = middle + 1;
    else high = middle;
  }
  return low;
}

// Range of entries with prefix.
export function prefixRange(sorted: string[], prefix: string): [number, number] {
  return [lowerBound(sorted, prefix), lowerBound(sorted, prefix + "￿")];
}

export function hasPrefix(sorted: string[], prefix: string) {
  const [from, to] = prefixRange(sorted, prefix);
  return from < to;
}

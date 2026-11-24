const tabs = ["files", "history", "inputs", "access"] as const;

export type SourceTab = (typeof tabs)[number];

// The Source page lives in its URL.
export type SourceSearch = { tab?: SourceTab; path?: string; commit?: string; create?: boolean };

export function parseSourceSearch(search: Record<string, unknown>): SourceSearch {
  return {
    tab: tabs.find((each) => each === search.tab),
    path: typeof search.path === "string" && search.path !== "" ? search.path : undefined,
    commit: typeof search.commit === "string" ? search.commit : undefined,
    create: search.create === true ? true : undefined,
  };
}

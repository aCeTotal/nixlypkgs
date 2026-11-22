import { keepPreviousData, queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";

export const minQuery = 2;

export const attrPattern = /^[A-Za-z_][A-Za-z0-9_'-]*(\.[A-Za-z_][A-Za-z0-9_'-]*)*$/;

export const searchQuery = (query: string) =>
  queryOptions({
    queryKey: ["nixpkgs", query],
    queryFn: ({ signal }) => api<string[]>(`/nixpkgs?q=${encodeURIComponent(query)}`, { signal }),
    enabled: query.length >= minQuery,
    staleTime: 5 * 60_000,
    placeholderData: keepPreviousData,
  });

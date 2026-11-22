import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { ApiError } from "./http";

export const sessionQueryKey = "session";

function isClientError(error: unknown) {
  return error instanceof ApiError && error.status >= 400 && error.status < 500;
}

export const queryClient = new QueryClient({
  queryCache: new QueryCache({
    onError: (error, query) => {
      if (error instanceof ApiError && error.status === 401 && query.queryKey[0] !== sessionQueryKey) {
        window.location.assign(`/login?redirect=${encodeURIComponent(window.location.pathname)}`);
      }
    },
  }),
  mutationCache: new MutationCache({
    onError: (error, _variables, _context, mutation) => {
      if (!mutation.options.onError) toast.error(error.message);
    },
  }),
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      refetchOnWindowFocus: false,
      retry: (failures, error) => !isClientError(error) && failures < 2,
    },
  },
});

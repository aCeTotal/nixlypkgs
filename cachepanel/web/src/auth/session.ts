import { queryOptions, useSuspenseQuery } from "@tanstack/react-query";
import { api, setCsrfToken } from "@/api/http";
import { queryClient, sessionQueryKey } from "@/api/query-client";
import { disconnectRealtime } from "@/api/realtime";

export type User = { id: number; username: string };

type Session = { user: User; csrf: string };

function remember(session: Session) {
  setCsrfToken(session.csrf);
  queryClient.setQueryData(sessionQuery.queryKey, session.user);
  return session.user;
}

export const sessionQuery = queryOptions({
  queryKey: [sessionQueryKey],
  queryFn: async () => remember(await api<Session>("/auth/me")),
  staleTime: Infinity,
  retry: false,
});

export async function login(username: string, password: string) {
  return remember(await api<Session>("/auth/login", { method: "POST", body: { username, password } }));
}

export async function logout() {
  await api("/auth/logout", { method: "POST" });
  disconnectRealtime();
  queryClient.clear();
}

export function changePassword(current: string, next: string) {
  return api("/auth/password", { method: "POST", body: { current, next } });
}

export function useUser() {
  return useSuspenseQuery(sessionQuery).data;
}

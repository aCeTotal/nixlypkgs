import { createRootRouteWithContext, createRoute, Outlet, redirect } from "@tanstack/react-router";
import type { QueryClient } from "@tanstack/react-query";
import { ApiError } from "@/api/http";
import { connectRealtime } from "@/api/realtime";
import { sessionQuery } from "@/auth/session";
import { AppShell } from "./app-shell";
import { NotFound } from "./not-found";
import { RouteError } from "./route-error";

declare module "@tanstack/react-router" {
  interface StaticDataRouteOption {
    title?: string;
  }
}

type RouterContext = { queryClient: QueryClient };

export const rootRoute = createRootRouteWithContext<RouterContext>()({
  component: Outlet,
  notFoundComponent: NotFound,
  errorComponent: RouteError,
});

export const appRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: "app",
  beforeLoad: async ({ context, location }) => {
    await context.queryClient.ensureQueryData(sessionQuery).catch((error: unknown) => {
      if (error instanceof ApiError && error.status === 401) {
        throw redirect({ to: "/login", search: { redirect: location.href } });
      }
      throw error;
    });
    connectRealtime();
  },
  component: AppShell,
  notFoundComponent: NotFound,
});

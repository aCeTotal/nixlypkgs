import { createRoute, createRouter } from "@tanstack/react-router";
import { queryClient } from "@/api/query-client";
import { LoginPage } from "@/auth/login-page";
import { CommitsPage } from "@/commits/commits-page";
import { commitsQuery } from "@/commits/queries";
import { ModulePage } from "@/modules/module-page";
import { ModulesPage } from "@/modules/modules-page";
import { moduleQuery, modulesQuery } from "@/modules/queries";
import { OverviewPage } from "@/overview/overview-page";
import { overviewQuery } from "@/overview/queries";
import { PackagePage } from "@/packages/package-page";
import { PackagesPage } from "@/packages/packages-page";
import { packageQuery, packagesQuery } from "@/packages/queries";
import { appRoute, rootRoute } from "@/shell/app-route";
import { ProfilePage } from "@/profiles/profile-page";
import { ProfilesPage } from "@/profiles/profiles-page";
import { profileQuery, profilesQuery } from "@/profiles/queries";
import { NewRecipePage } from "@/recipes/new-recipe-page";
import { recipeQuery, recipesQuery } from "@/recipes/queries";
import { RecipePage } from "@/recipes/recipe-page";
import { RecipesPage } from "@/recipes/recipes-page";

const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/login",
  validateSearch: (search: Record<string, unknown>) => ({ redirect: typeof search.redirect === "string" ? search.redirect : undefined }),
  component: LoginPage,
  staticData: { title: "Logg inn" },
});

const page = (path: string, title: string, component: () => React.ReactNode, loader?: () => Promise<unknown>) =>
  createRoute({ getParentRoute: () => appRoute, path, component, loader, staticData: { title } });

const routeTree = rootRoute.addChildren([
  loginRoute,
  appRoute.addChildren([
    page("/", "Oversikt", OverviewPage, () => queryClient.ensureQueryData(overviewQuery)),
    page("/profiles", "Profiler", ProfilesPage, () => queryClient.ensureQueryData(profilesQuery)),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/profiles/$name",
      component: ProfilePage,
      loader: ({ params }) => queryClient.ensureQueryData(profileQuery(params.name)),
      staticData: { title: "Profil" },
    }),
    page("/modules", "Moduler", ModulesPage, () =>
      Promise.all([queryClient.ensureQueryData(modulesQuery), queryClient.ensureQueryData(profilesQuery)]),
    ),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/modules/$id",
      component: ModulePage,
      loader: ({ params }) => queryClient.ensureQueryData(moduleQuery(Number(params.id))),
      staticData: { title: "Modul" },
    }),
    page("/packages", "Pakker", PackagesPage, () => queryClient.ensureQueryData(packagesQuery)),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/packages/$attr",
      component: PackagePage,
      loader: ({ params }) => queryClient.ensureQueryData(packageQuery(params.attr)),
      staticData: { title: "Pakke" },
    }),
    page("/commits", "Commits", CommitsPage, () => queryClient.ensureInfiniteQueryData(commitsQuery)),
    page("/recipes", "Nye pakker", RecipesPage, () => queryClient.ensureQueryData(recipesQuery)),
    page("/recipes/new", "Ny pakke", NewRecipePage),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/recipes/$id",
      component: RecipePage,
      loader: ({ params }) => queryClient.ensureQueryData(recipeQuery(Number(params.id))),
      staticData: { title: "Ny pakke" },
    }),
  ]),
]);

export const router = createRouter({
  routeTree,
  context: { queryClient },
  defaultPreload: "intent",
  defaultPreloadStaleTime: 0,
  scrollRestoration: true,
});

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}

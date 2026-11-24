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
import { approvalQuery, kernelsQuery, profileQuery, profilesQuery } from "@/profiles/queries";
import { TestingPage } from "@/profiles/testing-page";
import { NewRecipePage } from "@/recipes/new-recipe-page";
import { recipeQuery, recipesQuery } from "@/recipes/queries";
import { RecipePage } from "@/recipes/recipe-page";
import { RecipesPage } from "@/recipes/recipes-page";
import { sourceQuery, treeQuery } from "@/source/queries";
import { parseSourceSearch } from "@/source/search";
import { SourcePage } from "@/source/source-page";
import { updateQuery } from "@/update/queries";
import { trustQuery } from "@/trust/queries";
import { TrustPage } from "@/trust/trust-page";

const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/login",
  validateSearch: (search: Record<string, unknown>) => ({ redirect: typeof search.redirect === "string" ? search.redirect : undefined }),
  component: LoginPage,
  staticData: { title: "Sign in" },
});

const page = (path: string, title: string, component: () => React.ReactNode, loader?: () => Promise<unknown>) =>
  createRoute({ getParentRoute: () => appRoute, path, component, loader, staticData: { title } });

const routeTree = rootRoute.addChildren([
  loginRoute,
  appRoute.addChildren([
    page("/", "Overview", OverviewPage, () => queryClient.ensureQueryData(overviewQuery)),
    page("/profiles", "Profiles", ProfilesPage, () => queryClient.ensureQueryData(profilesQuery)),
    page("/testing", "Testing", TestingPage, () => queryClient.ensureQueryData(approvalQuery)),
    page("/trust", "Trust", TrustPage, () => queryClient.ensureQueryData(trustQuery)),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/profiles/$name",
      component: ProfilePage,
      loader: ({ params }) =>
        Promise.all([queryClient.ensureQueryData(profileQuery(params.name)), queryClient.ensureQueryData(kernelsQuery)]),
      staticData: { title: "Profile" },
    }),
    page("/modules", "Modules", ModulesPage, () =>
      Promise.all([queryClient.ensureQueryData(modulesQuery), queryClient.ensureQueryData(profilesQuery)]),
    ),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/modules/$slug",
      component: ModulePage,
      loader: ({ params }) => queryClient.ensureQueryData(moduleQuery(params.slug)),
      staticData: { title: "Module" },
    }),
    page("/packages", "Derivations", PackagesPage, () => queryClient.ensureQueryData(packagesQuery)),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/packages/$attr",
      component: PackagePage,
      loader: ({ params }) => queryClient.ensureQueryData(packageQuery(params.attr)),
      staticData: { title: "Derivation" },
    }),
    page("/commits", "Commits", CommitsPage, () => queryClient.ensureInfiniteQueryData(commitsQuery)),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/source",
      validateSearch: parseSourceSearch,
      component: SourcePage,
      loader: () =>
        Promise.all([
          queryClient.ensureQueryData(sourceQuery),
          queryClient.ensureQueryData(updateQuery),
          queryClient.ensureQueryData(treeQuery("")),
        ]),
      staticData: { title: "Source" },
    }),
    page("/recipes", "Add derivation", RecipesPage, () => queryClient.ensureQueryData(recipesQuery)),
    page("/recipes/new", "Add derivation", NewRecipePage),
    createRoute({
      getParentRoute: () => appRoute,
      path: "/recipes/$id",
      component: RecipePage,
      loader: ({ params }) => queryClient.ensureQueryData(recipeQuery(Number(params.id))),
      staticData: { title: "Add derivation" },
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

import { queryOptions } from "@tanstack/react-query";
import { api, upload } from "@/api/http";

export type RecipeState = "importing" | "draft" | "building" | "ready" | "failed" | "published";

export type Builder =
  | "makepkg"
  | "cmake"
  | "meson"
  | "autotools"
  | "make"
  | "cargo"
  | "go"
  | "python"
  | "npm"
  | "appimage"
  | "deb"
  | "rpm"
  | "prebuilt";

export type Origin = "aur" | "arch" | "pkgbuild" | "url" | "upload" | "github";

export type Source = {
  kind: "url" | "upload" | "github" | "git" | "file";
  name: string;
  url?: string;
  owner?: string;
  repo?: string;
  rev?: string;
  hash?: string;
  history?: boolean;
};

export type Spec = {
  attr: string;
  pname: string;
  version: string;
  builder: Builder;
  sources: Source[];
  root?: string;
  nativeBuildInputs: string[] | null;
  buildInputs: string[] | null;
  depends: string[] | null;
  pythonDependencies: string[] | null;
  buildSystem: string[] | null;
  flags: string[] | null;
  vendor?: string;
  vendorHash?: string;
  vendored?: boolean;
  noBuild?: boolean;
  subPackages?: string[];
  split?: string;
  noextract?: string[];
  noStrip?: boolean;
  layout: unknown;
  ignoredLibraries: string[] | null;
  meta: { description: string; homepage: string; license: string; mainProgram: string };
};

export type RecipeSummary = {
  id: number;
  attr: string | null;
  state: RecipeState;
  error: string | null;
  origin: { origin: Origin; name: string; url: string; files: string[] };
  pname: string | null;
  version: string | null;
  builder: Builder | null;
  description: string | null;
  publishedSha: string | null;
  updatedAt: string;
};

export type RecipeFile = { name: string; text: string; size: number };

export type RecipeDetail = {
  id: number;
  attr: string | null;
  state: RecipeState;
  error: string | null;
  origin: RecipeSummary["origin"];
  spec: Spec | null;
  report: { notes: string[] | null; steps: string[] | null; hints: string[] | null };
  output: string | null;
  publishedSha: string | null;
  files: RecipeFile[];
};

export type ImportRequest = {
  origin: Origin;
  name?: string;
  url?: string;
  ref?: string;
  upload?: string;
  files?: Record<string, string>;
};

export const builderLabels: Record<Builder, string> = {
  makepkg: "PKGBUILD",
  cmake: "CMake",
  meson: "Meson",
  autotools: "Autotools",
  make: "Make",
  cargo: "Rust (cargo)",
  go: "Go",
  python: "Python",
  npm: "Node (npm)",
  appimage: "AppImage",
  deb: "Debian package",
  rpm: "RPM package",
  prebuilt: "Prebuilt",
};

export const recipesQuery = queryOptions({ queryKey: ["recipes"], queryFn: () => api<RecipeSummary[]>("/recipes") });

export const recipeQuery = (id: number) =>
  queryOptions({ queryKey: ["recipe", id], queryFn: () => api<RecipeDetail>(`/recipes/${id}`) });

export const recipeLog = (id: number, from: number) => api<{ text: string; next: number }>(`/recipes/${id}/log?from=${from}`);

export const importRecipe = (body: ImportRequest) => api<{ id: number }>("/recipes", { method: "POST", body });

export const saveRecipe = (id: number, body: { spec: Spec; files?: Record<string, string> }) =>
  api(`/recipes/${id}`, { method: "PUT", body });

export const recipeAction = (id: number, action: "build" | "stop") => api(`/recipes/${id}/${action}`, { method: "POST" });

export const publishRecipe = (id: number) => api<{ sha: string }>(`/recipes/${id}/publish`, { method: "POST" });

export const deleteRecipe = (id: number) => api(`/recipes/${id}`, { method: "DELETE" });

export const uploadSource = (file: File, onProgress: (fraction: number) => void) =>
  upload<{ hash: string; name: string; url: string }>("/sources", file, onProgress);

export const publishingQuery = queryOptions({
  queryKey: ["publishing"],
  queryFn: () => api<{ remote: string | null; publicKey: string | null }>("/publishing"),
  staleTime: Infinity,
});

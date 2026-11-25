import { StreamLanguage, type StreamParser } from "@codemirror/language";
import type { Extension } from "@codemirror/state";
import { nix } from "./nix/language";

type Loader = () => Promise<Extension>;

const legacy = (parser: Promise<StreamParser<unknown>>) => parser.then((mode) => StreamLanguage.define(mode));

const shell: Loader = () => legacy(import("@codemirror/legacy-modes/mode/shell").then((m) => m.shell));
const javascript = (options: { typescript?: boolean; jsx?: boolean }): Loader => () =>
  import("@codemirror/lang-javascript").then((m) => m.javascript(options));
const json: Loader = () => import("@codemirror/lang-json").then((m) => m.json());
const cpp: Loader = () => import("@codemirror/lang-cpp").then((m) => m.cpp());

// Languages load on first use.
const byExtension: Record<string, Loader> = {
  nix: async () => nix(),
  sh: shell,
  bash: shell,
  ts: javascript({ typescript: true }),
  tsx: javascript({ typescript: true, jsx: true }),
  js: javascript({}),
  mjs: javascript({}),
  jsx: javascript({ jsx: true }),
  json,
  lock: json,
  go: () => import("@codemirror/lang-go").then((m) => m.go()),
  py: () => import("@codemirror/lang-python").then((m) => m.python()),
  md: () => import("@codemirror/lang-markdown").then((m) => m.markdown()),
  yaml: () => import("@codemirror/lang-yaml").then((m) => m.yaml()),
  yml: () => import("@codemirror/lang-yaml").then((m) => m.yaml()),
  css: () => import("@codemirror/lang-css").then((m) => m.css()),
  html: () => import("@codemirror/lang-html").then((m) => m.html()),
  c: cpp,
  h: cpp,
  cc: cpp,
  cpp,
  hpp: cpp,
  toml: () => legacy(import("@codemirror/legacy-modes/mode/toml").then((m) => m.toml)),
  patch: () => legacy(import("@codemirror/legacy-modes/mode/diff").then((m) => m.diff)),
  diff: () => legacy(import("@codemirror/legacy-modes/mode/diff").then((m) => m.diff)),
  conf: () => legacy(import("@codemirror/legacy-modes/mode/properties").then((m) => m.properties)),
};

const byName: Record<string, Loader> = {
  PKGBUILD: shell,
  Dockerfile: () => legacy(import("@codemirror/legacy-modes/mode/dockerfile").then((m) => m.dockerFile)),
};

export const isNix = (path: string) => path.endsWith(".nix");

export function loadLanguage(path: string): Promise<Extension> {
  const name = path.slice(path.lastIndexOf("/") + 1);
  const extension = name.includes(".") ? name.slice(name.lastIndexOf(".") + 1) : "";
  const loader = byName[name] ?? byExtension[extension];
  return loader ? loader() : Promise.resolve([]);
}

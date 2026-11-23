import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Field, FieldDescription, FieldLabel } from "@/ui/field";
import { Textarea } from "@/ui/textarea";
import { AttrList } from "./attr-list";
import type { Builder, Spec } from "./queries";

type ListKey = "nativeBuildInputs" | "buildInputs" | "depends" | "pythonDependencies" | "buildSystem";

type Group = { key: ListKey; title: string; hint: string };

const tools: Group = { key: "nativeBuildInputs", title: "Build tools", hint: "Tools the build runs, such as cmake, cargo or pkg-config." };
const libraries: Group = { key: "buildInputs", title: "Libraries", hint: "Libraries the program links against." };

const groups: Partial<Record<Builder, Group[]>> = {
  makepkg: [
    tools,
    { key: "depends", title: "Runtime", hint: "What the package needs when it runs (depends in the PKGBUILD)." },
    { key: "pythonDependencies", title: "Python modules", hint: "Modules a Python program imports." },
    { ...libraries, title: "Extra libraries", hint: "Libraries only the build needs." },
  ],
  python: [
    { key: "buildSystem", title: "Build system", hint: "What pyproject.toml builds with, such as setuptools or hatchling." },
    { key: "pythonDependencies", title: "Python modules", hint: "Modules the program imports." },
    tools,
    libraries,
  ],
};

const flagLabels: Partial<Record<Builder, string>> = {
  cmake: "cmakeFlags",
  meson: "mesonFlags",
  autotools: "configureFlags",
  make: "makeFlags",
  python: "pypaBuildFlags",
};

const prebuilt = new Set<Builder>(["makepkg", "deb", "rpm", "prebuilt"]);

const lines = (text: string) => text.split("\n").map((line) => line.trim()).filter(Boolean);

type RecipeDepsProps = { spec: Spec; update: (change: Partial<Spec>) => void };

export function RecipeDeps({ spec, update }: RecipeDepsProps) {
  const shown = groups[spec.builder] ?? [tools, libraries];
  const flags = flagLabels[spec.builder];
  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_24rem]">
      <div className="grid gap-4 lg:grid-cols-2">
        {shown.map((group) => (
          <AttrList
            key={group.key}
            title={group.title}
            hint={group.hint}
            attrs={spec[group.key] ?? []}
            onChange={(attrs) => update({ [group.key]: attrs })}
          />
        ))}
      </div>
      <div className="space-y-4">
        {flags && (
          <Card>
            <CardHeader>
              <CardTitle>Build flags</CardTitle>
              <CardDescription>One flag per line.</CardDescription>
            </CardHeader>
            <CardContent>
              <Field>
                <FieldLabel htmlFor="flags" className="font-mono">
                  {flags}
                </FieldLabel>
                <Textarea id="flags" rows={5} className="font-mono text-xs" value={(spec.flags ?? []).join("\n")} onChange={(event) => update({ flags: lines(event.target.value) })} />
              </Field>
            </CardContent>
          </Card>
        )}
        {prebuilt.has(spec.builder) && (
          <Card>
            <CardHeader>
              <CardTitle>Optional libraries</CardTitle>
              <CardDescription>Libraries the program manages without, even if its files ask for them.</CardDescription>
            </CardHeader>
            <CardContent>
              <Field>
                <FieldLabel htmlFor="ignored">One file name per line</FieldLabel>
                <Textarea
                  id="ignored"
                  rows={4}
                  className="font-mono text-xs"
                  placeholder="libcuda.so.1"
                  value={(spec.ignoredLibraries ?? []).join("\n")}
                  onChange={(event) => update({ ignoredLibraries: lines(event.target.value) })}
                />
                <FieldDescription>The test build adds what nixpkgs has; list the rest here.</FieldDescription>
              </Field>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}

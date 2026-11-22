import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Field, FieldDescription, FieldLabel } from "@/ui/field";
import { Textarea } from "@/ui/textarea";
import { AttrList } from "./attr-list";
import type { Builder, Spec } from "./queries";

type ListKey = "nativeBuildInputs" | "buildInputs" | "depends" | "pythonDependencies" | "buildSystem";

type Group = { key: ListKey; title: string; hint: string };

const tools: Group = { key: "nativeBuildInputs", title: "Byggeverktøy", hint: "Verktøy bygget kjører, som cmake, cargo eller pkg-config." };
const libraries: Group = { key: "buildInputs", title: "Biblioteker", hint: "Biblioteker programmet lenkes mot." };

const groups: Partial<Record<Builder, Group[]>> = {
  makepkg: [
    tools,
    { key: "depends", title: "Kjøretid", hint: "Det pakken trenger når den kjører (depends i PKGBUILD-en)." },
    { key: "pythonDependencies", title: "Python-moduler", hint: "Moduler et Python-program importerer." },
    { ...libraries, title: "Ekstra biblioteker", hint: "Biblioteker bare bygget trenger." },
  ],
  python: [
    { key: "buildSystem", title: "Byggesystem", hint: "Det pyproject.toml bygger med, som setuptools eller hatchling." },
    { key: "pythonDependencies", title: "Python-moduler", hint: "Moduler programmet importerer." },
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
              <CardTitle>Byggeflagg</CardTitle>
              <CardDescription>Ett flagg per linje.</CardDescription>
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
              <CardTitle>Valgfrie biblioteker</CardTitle>
              <CardDescription>Biblioteker programmet klarer seg uten, selv om filene ber om dem.</CardDescription>
            </CardHeader>
            <CardContent>
              <Field>
                <FieldLabel htmlFor="ignored">Ett filnavn per linje</FieldLabel>
                <Textarea
                  id="ignored"
                  rows={4}
                  className="font-mono text-xs"
                  placeholder="libcuda.so.1"
                  value={(spec.ignoredLibraries ?? []).join("\n")}
                  onChange={(event) => update({ ignoredLibraries: lines(event.target.value) })}
                />
                <FieldDescription>Testbygget legger til det som finnes i nixpkgs; resten kan listes her.</FieldDescription>
              </Field>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}

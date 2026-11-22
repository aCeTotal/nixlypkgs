import { useSuspenseQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { Cpu, Lock } from "lucide-react";
import { catalogQuery } from "@/modules/queries";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Checkbox } from "@/ui/checkbox";
import type { ProfileCatalogModule, ProfileDetail, ProfileSettings } from "./queries";

type ProfileModulesProps = {
  detail: ProfileDetail;
  draft: ProfileSettings;
  update: (change: Partial<ProfileSettings>) => void;
};

function toggled<T>(list: T[], value: T, on: boolean) {
  return on ? [...list, value] : list.filter((item) => item !== value);
}

export function ProfileModules({ detail, draft, update }: ProfileModulesProps) {
  const { data: catalog } = useSuspenseQuery(catalogQuery);
  const groups = catalog.categories
    .map((category) => ({ ...category, modules: detail.catalog.filter((module) => module.category === category.name) }))
    .filter((group) => group.modules.length > 0);
  const setGroup = (modules: ProfileCatalogModule[], on: boolean) => {
    const names = modules.filter((module) => !module.required).map((module) => module.name);
    update({ catalog: on ? [...new Set([...draft.catalog, ...names])] : draft.catalog.filter((name) => !names.includes(name)) });
  };
  return (
    <div className="space-y-4">
      <div className="grid gap-4 xl:grid-cols-2">
        {groups.map((group) => {
          const chosen = group.modules.filter((module) => module.required || draft.catalog.includes(module.name)).length;
          return (
            <Card key={group.name}>
              <CardHeader>
                <CardTitle>{group.title}</CardTitle>
                <CardDescription>
                    {chosen} av {group.modules.length} valgt
                  </CardDescription>
                <CardAction className="flex gap-1">
                  <Button size="sm" variant="ghost" onClick={() => setGroup(group.modules, true)}>
                    Alle
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setGroup(group.modules, false)}>
                    Ingen
                  </Button>
                </CardAction>
              </CardHeader>
              <CardContent className="grid gap-1 sm:grid-cols-2">
                {group.modules.map((module) => (
                  <div key={module.name} className="flex items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-muted/60">
                    <Checkbox
                      id={`catalog-${module.name}`}
                      disabled={module.required}
                      checked={module.required || draft.catalog.includes(module.name)}
                      onCheckedChange={(on) => update({ catalog: toggled(draft.catalog, module.name, on === true) })}
                    />
                    <label htmlFor={`catalog-${module.name}`} className="min-w-0 flex-1 cursor-pointer">
                      <span className="block truncate text-sm font-medium">{module.title}</span>
                      <span className="block font-mono text-xs text-muted-foreground">{module.name}</span>
                    </label>
                    {module.required && (
                      <Badge variant="secondary" className="gap-1">
                        <Lock className="size-3" />
                        Påkrevd
                      </Badge>
                    )}
                    {module.x86Only && <Badge variant="outline">x86</Badge>}
                    {!module.present && <Badge variant="destructive">Fjernet</Badge>}
                  </div>
                ))}
              </CardContent>
            </Card>
          );
        })}
      </div>
      <div className="grid gap-4 xl:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Panelmoduler</CardTitle>
            <CardDescription>Egne NixOS-moduler skrevet i panelet, for å teste nye ting.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            {detail.modules.length === 0 && (
              <p className="text-sm text-muted-foreground">
                Ingen panelmoduler ennå.{" "}
                <Link to="/modules" className="text-primary hover:underline">
                  Lag en i registeret.
                </Link>
              </p>
            )}
            {detail.modules.map((module) => (
              <div key={module.id} className="flex items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-muted/60">
                <Checkbox
                  id={`module-${module.id}`}
                  checked={draft.modules.includes(module.id)}
                  onCheckedChange={(on) => update({ modules: toggled(draft.modules, module.id, on === true) })}
                />
                <label htmlFor={`module-${module.id}`} className="min-w-0 flex-1 cursor-pointer">
                  <span className="block truncate text-sm font-medium">{module.title}</span>
                  <span className="block font-mono text-xs text-muted-foreground">{module.slug}.nix</span>
                </label>
                <Link to="/modules/$id" params={{ id: String(module.id) }} className="text-xs text-primary hover:underline">
                  Rediger
                </Link>
              </div>
            ))}
          </CardContent>
        </Card>
        <Card className="bg-muted/30">
          <CardContent className="flex gap-3 text-sm text-muted-foreground">
            <Cpu className="mt-0.5 size-4 shrink-0 text-primary" />
            <p>
              Maskinvaremoduler (CPU, GPU, virtualisering, modellprofil) velges automatisk på hver maskin ut fra
              nixlyos-detect-hw. Profilen testes på alle referansemaskinene før den rulles ut.
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

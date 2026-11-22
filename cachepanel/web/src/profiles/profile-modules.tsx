import { Link } from "@tanstack/react-router";
import { Cpu, Lock } from "lucide-react";
import { Badge } from "@/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Checkbox } from "@/ui/checkbox";
import type { ProfileDetail, ProfileModule, ProfileSettings } from "./queries";

type ProfileModulesProps = {
  detail: ProfileDetail;
  draft: ProfileSettings;
  update: (change: Partial<ProfileSettings>) => void;
};

export function ProfileModules({ detail, draft, update }: ProfileModulesProps) {
  const toggle = (id: number, on: boolean) =>
    update({ modules: on ? [...draft.modules, id] : draft.modules.filter((module) => module !== id) });
  const required = detail.modules.filter((module) => module.required);
  const optional = detail.modules.filter((module) => !module.required);
  const chosen = optional.filter((module) => draft.modules.includes(module.id)).length;
  return (
    <div className="grid gap-4 xl:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Valgfrie moduler</CardTitle>
          <CardDescription>
            {chosen} av {optional.length} valgt for {detail.profile.title}.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-1">
          {optional.map((module) => (
            <ModuleRow key={module.id} module={module} checked={draft.modules.includes(module.id)} onChange={(on) => toggle(module.id, on)} />
          ))}
        </CardContent>
      </Card>
      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Påkrevd</CardTitle>
            <CardDescription>Med i alle profiler.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            {required.map((module) => (
              <ModuleRow key={module.id} module={module} checked />
            ))}
          </CardContent>
        </Card>
        <Card className="bg-muted/30">
          <CardContent className="flex gap-3 text-sm text-muted-foreground">
            <Cpu className="mt-0.5 size-4 shrink-0 text-primary" />
            <p>
              Maskinvaremodulen velger CPU-, GPU- og virtualiseringsoppsett på hver maskin ut fra nixlyos-detect-hw. Profilen
              testes på alle referansemaskinene før den rulles ut.
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function ModuleRow({ module, checked, onChange }: { module: ProfileModule; checked: boolean; onChange?: (on: boolean) => void }) {
  return (
    <div className="flex items-start gap-3 rounded-lg px-2 py-2 hover:bg-muted/60">
      <Checkbox
        id={`module-${module.id}`}
        className="mt-0.5"
        disabled={!onChange}
        checked={checked}
        onCheckedChange={(on) => onChange?.(on === true)}
      />
      <label htmlFor={`module-${module.id}`} className="min-w-0 flex-1 cursor-pointer">
        <span className="flex items-center gap-2 text-sm font-medium">
          {module.title}
          <span className="font-mono text-xs font-normal text-muted-foreground">{module.slug}.nix</span>
        </span>
        {module.description && <span className="block text-xs text-muted-foreground">{module.description}</span>}
      </label>
      {module.required && (
        <Badge variant="secondary" className="gap-1">
          <Lock className="size-3" />
          Påkrevd
        </Badge>
      )}
      <Link to="/modules/$id" params={{ id: String(module.id) }} className="shrink-0 text-xs text-primary hover:underline">
        Åpne
      </Link>
    </div>
  );
}

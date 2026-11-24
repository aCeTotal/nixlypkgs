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
  const toggle = (slug: string, on: boolean) =>
    update({ modules: on ? [...draft.modules, slug] : draft.modules.filter((module) => module !== slug) });
  const required = detail.modules.filter((module) => module.required);
  const optional = detail.modules.filter((module) => !module.required);
  const chosen = optional.filter((module) => draft.modules.includes(module.slug)).length;
  return (
    <div className="grid gap-4 xl:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Optional modules</CardTitle>
          <CardDescription>
            {chosen} of {optional.length} chosen for {detail.profile.title}.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-1">
          {optional.map((module) => (
            <ModuleRow key={module.slug} module={module} checked={draft.modules.includes(module.slug)} onChange={(on) => toggle(module.slug, on)} />
          ))}
        </CardContent>
      </Card>
      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Required</CardTitle>
            <CardDescription>In every profile.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            {required.map((module) => (
              <ModuleRow key={module.slug} module={module} checked />
            ))}
          </CardContent>
        </Card>
        <Card className="bg-muted/30">
          <CardContent className="flex gap-3 text-sm text-muted-foreground">
            <Cpu className="mt-0.5 size-4 shrink-0 text-primary" />
            <p>
              The hardware module picks CPU, GPU and virtualisation setup on each machine from nixlyos-detect-hw. Every
              profile is checked on all reference machines before it reaches testing.
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
        id={`module-${module.slug}`}
        className="mt-0.5"
        disabled={!onChange}
        checked={checked}
        onCheckedChange={(on) => onChange?.(on === true)}
      />
      <label htmlFor={`module-${module.slug}`} className="min-w-0 flex-1 cursor-pointer">
        <span className="flex items-center gap-2 text-sm font-medium">
          {module.title}
          <span className="font-mono text-xs font-normal text-muted-foreground">{module.slug}.nix</span>
        </span>
        {module.description && <span className="block text-xs text-muted-foreground">{module.description}</span>}
      </label>
      {module.required && (
        <Badge variant="secondary" className="gap-1">
          <Lock className="size-3" />
          Required
        </Badge>
      )}
      <Link to="/modules/$slug" params={{ slug: module.slug }} className="shrink-0 text-xs text-primary hover:underline">
        Open
      </Link>
    </div>
  );
}

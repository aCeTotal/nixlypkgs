import { useSuspenseQuery } from "@tanstack/react-query";
import { Link, useNavigate } from "@tanstack/react-router";
import { Blocks, Check, FileCode, Lock, ShieldCheck } from "lucide-react";
import { timeAgo } from "@/format/time";
import { PlatformIcon } from "@/profiles/platform-icon";
import { profilesQuery, type ProfileSummary } from "@/profiles/queries";
import { PageHeader } from "@/shell/page-header";
import { StatTile } from "@/shell/stat-tile";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/ui/table";
import { NewModuleDialog } from "./new-module-dialog";
import { modulesQuery, type ModuleSummary } from "./queries";

export function ModulesPage() {
  const { data: modules } = useSuspenseQuery(modulesQuery);
  const { data: profiles } = useSuspenseQuery(profilesQuery);
  const required = modules.filter((module) => module.required);
  const optional = modules.filter((module) => !module.required);
  const lines = modules.reduce((sum, module) => sum + module.lines, 0);
  return (
    <div className="space-y-5">
      <PageHeader
        title="Modules"
        description="Everything the systems are built from. Required modules are in every profile; optional ones are chosen per profile. The order is the import order."
        actions={<NewModuleDialog />}
      />
      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Modules" value={modules.length} hint={`${lines.toLocaleString("en-GB")} lines of Nix`} icon={Blocks} />
        <StatTile label="Required" value={required.length} hint="In every profile" icon={ShieldCheck} tone="info" />
        <StatTile label="Profiles" value={profiles.length} hint="Checked before rollout" icon={FileCode} tone="success" />
      </div>
      <div className="overflow-hidden rounded-xl border bg-card shadow-sm">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-full min-w-72">Module</TableHead>
              {profiles.map((profile) => (
                <TableHead key={profile.id} className="px-3 text-center">
                  <Link
                    to="/profiles/$name"
                    params={{ name: profile.name }}
                    className="inline-flex items-center gap-1.5 font-medium text-foreground hover:text-primary"
                  >
                    <PlatformIcon platform={profile.platform} className="size-3.5 text-muted-foreground" />
                    {profile.title}
                  </Link>
                </TableHead>
              ))}
              <TableHead className="text-right">Lines</TableHead>
              <TableHead className="text-right whitespace-nowrap">Changed</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <Group title="Required" modules={required} profiles={profiles} />
            <Group title="Optional" modules={optional} profiles={profiles} />
          </TableBody>
        </Table>
      </div>
    </div>
  );
}

function Group({ title, modules, profiles }: { title: string; modules: ModuleSummary[]; profiles: ProfileSummary[] }) {
  const navigate = useNavigate();
  if (modules.length === 0) return null;
  return (
    <>
      <TableRow className="bg-muted/40 hover:bg-muted/40">
        <TableCell colSpan={profiles.length + 3} className="py-1.5 text-xs font-semibold tracking-wide text-muted-foreground uppercase">
          {title}
        </TableCell>
      </TableRow>
      {modules.map((module) => (
        <TableRow
          key={module.id}
          onClick={() => navigate({ to: "/modules/$id", params: { id: String(module.id) } })}
          className="group cursor-pointer"
        >
          <TableCell className="whitespace-normal">
            <Link
              to="/modules/$id"
              params={{ id: String(module.id) }}
              className="font-medium group-hover:text-primary"
              onClick={(event) => event.stopPropagation()}
            >
              {module.title}
            </Link>
            <p className="font-mono text-xs text-muted-foreground">{module.slug}.nix</p>
            {module.description && <p className="mt-0.5 text-sm text-muted-foreground">{module.description}</p>}
          </TableCell>
          {profiles.map((profile) => (
            <TableCell key={profile.id} className="px-3 text-center">
              <Usage module={module} profile={profile} />
            </TableCell>
          ))}
          <TableCell className="text-right tabular-nums">{module.lines.toLocaleString("nb-NO")}</TableCell>
          <TableCell className="text-right text-sm whitespace-nowrap text-muted-foreground">{timeAgo(module.updatedAt)}</TableCell>
        </TableRow>
      ))}
    </>
  );
}

function Usage({ module, profile }: { module: ModuleSummary; profile: ProfileSummary }) {
  if (module.required) {
    return (
      <span title="Required" className="inline-grid size-6 place-items-center rounded-full bg-info-soft text-info">
        <Lock className="size-3.5" />
      </span>
    );
  }
  if (!module.usedBy.some((user) => user.name === profile.name)) {
    return <span className="inline-block size-1.5 rounded-full bg-border" aria-label="Not chosen" />;
  }
  return (
    <span title="Chosen" className="inline-grid size-6 place-items-center rounded-full bg-success-soft text-success">
      <Check className="size-3.5" />
    </span>
  );
}

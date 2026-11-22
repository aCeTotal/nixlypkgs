import { useMutation, useSuspenseQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { Lock, Search } from "lucide-react";
import { useDeferredValue, useState } from "react";
import { formatDuration } from "@/format/duration";
import { PageHeader } from "@/shell/page-header";
import { Badge } from "@/ui/badge";
import { Input } from "@/ui/input";
import { Switch } from "@/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/ui/table";
import { ToggleGroup, ToggleGroupItem } from "@/ui/toggle-group";
import { packagesQuery, setAutoBuild, type PackageSummary } from "./queries";
import { VersionPills } from "./version-pills";

const filters = {
  all: { label: "Alle", test: () => true },
  building: { label: "Bygger", test: (p: PackageSummary) => p.versions.some((v) => v.state === "building" || v.state === "queued") },
  failed: { label: "Feilet", test: (p: PackageSummary) => p.versions.some((v) => v.state === "failed") || p.evalError !== null },
  pinned: { label: "Låst", test: (p: PackageSummary) => p.selectedVersionId !== null },
  manual: { label: "Manuell", test: (p: PackageSummary) => !p.autoBuild },
} as const;

type Filter = keyof typeof filters;

export function PackagesPage() {
  const { data } = useSuspenseQuery(packagesQuery);
  const [filter, setFilter] = useState<Filter>("all");
  const [search, setSearch] = useState("");
  const query = useDeferredValue(search.trim().toLowerCase());
  const toggle = useMutation({ mutationFn: ({ attr, enabled }: { attr: string; enabled: boolean }) => setAutoBuild(attr, enabled) });
  const shown = data.filter((pkg) => filters[filter].test(pkg) && pkg.attr.toLowerCase().includes(query));
  return (
    <div className="space-y-4">
      <PageHeader
        title="Pakker"
        description="Hver pakke beholder sine tre siste derivasjoner i cachen. Nye commits bygges automatisk."
      />
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative w-full max-w-xs">
          <Search className="absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Søk etter pakke" className="pl-8" />
        </div>
        <ToggleGroup type="single" variant="outline" value={filter} onValueChange={(value) => value && setFilter(value as Filter)}>
          {Object.entries(filters).map(([key, { label }]) => (
            <ToggleGroupItem key={key} value={key}>
              {label}
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
        <span className="ml-auto text-sm text-muted-foreground">{shown.length} pakker</span>
      </div>
      <div className="overflow-hidden rounded-xl border bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Pakke</TableHead>
              <TableHead>Versjoner</TableHead>
              <TableHead>Valg</TableHead>
              <TableHead className="text-right">Byggetid</TableHead>
              <TableHead className="text-right">Auto</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {shown.map((pkg) => (
              <TableRow key={pkg.attr} className={pkg.present ? undefined : "opacity-60"}>
                <TableCell className="max-w-80">
                  <Link to="/packages/$attr" params={{ attr: pkg.attr }} className="font-medium hover:text-primary hover:underline">
                    {pkg.attr}
                  </Link>
                  <p className="truncate text-xs text-muted-foreground">{pkg.versions[0]?.name ?? "Ingen versjoner"}</p>
                </TableCell>
                <TableCell>
                  <VersionPills versions={pkg.versions} selected={pkg.selectedVersionId} />
                </TableCell>
                <TableCell>
                  {pkg.selectedVersionId !== null ? (
                    <Badge variant="secondary">
                      <Lock />
                      Låst
                    </Badge>
                  ) : (
                    <span className="text-sm text-muted-foreground">Følger systemet</span>
                  )}
                  {!pkg.present && <Badge variant="outline" className="ml-1.5">Fjernet</Badge>}
                  {pkg.evalError && <Badge variant="destructive" className="ml-1.5">Evalueringsfeil</Badge>}
                </TableCell>
                <TableCell className="text-right text-sm text-muted-foreground tabular-nums">{formatDuration(pkg.expectedSeconds)}</TableCell>
                <TableCell className="text-right">
                  <Switch
                    aria-label={`Bygg ${pkg.attr} automatisk`}
                    checked={pkg.autoBuild}
                    onCheckedChange={(enabled) => toggle.mutate({ attr: pkg.attr, enabled })}
                  />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}

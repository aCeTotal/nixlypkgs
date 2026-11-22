import { useMutation, useSuspenseQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { ArrowLeft, Info } from "lucide-react";
import { formatDuration } from "@/format/duration";
import { PageHeader } from "@/shell/page-header";
import { Alert, AlertDescription, AlertTitle } from "@/ui/alert";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Card, CardContent } from "@/ui/card";
import { Switch } from "@/ui/switch";
import { packageQuery, setAutoBuild } from "./queries";
import { VersionCard } from "./version-card";

const route = getRouteApi("/app/packages/$attr");

export function PackagePage() {
  const { attr } = route.useParams();
  const { data: pkg } = useSuspenseQuery(packageQuery(attr));
  const toggle = useMutation({ mutationFn: (enabled: boolean) => setAutoBuild(attr, enabled) });
  return (
    <div className="space-y-5">
      <Button asChild variant="ghost" size="sm" className="-ml-2">
        <Link to="/packages">
          <ArrowLeft />
          Alle pakker
        </Link>
      </Button>
      <PageHeader
        title={pkg.attr}
        description={pkg.present ? "packages.x86_64-linux i nixlypkgs" : "Finnes ikke lenger i nixlypkgs – cachen beholdes til du sletter den."}
        actions={!pkg.present && <Badge variant="outline">Fjernet fra nixlypkgs</Badge>}
      />
      {pkg.evalError && (
        <Alert variant="destructive">
          <AlertTitle>Evalueringsfeil i nyeste commit</AlertTitle>
          <AlertDescription>
            <pre className="max-h-48 overflow-auto font-mono text-xs whitespace-pre-wrap">{pkg.evalError}</pre>
          </AlertDescription>
        </Alert>
      )}
      <Card>
        <CardContent className="flex flex-wrap items-center gap-x-10 gap-y-4">
          <div className="flex items-center gap-3">
            <Switch id="auto-build" checked={pkg.autoBuild} onCheckedChange={(enabled) => toggle.mutate(enabled)} />
            <label htmlFor="auto-build">
              <span className="block font-medium">Bygg automatisk</span>
              <span className="block text-sm text-muted-foreground">Nye derivasjoner settes i kø med en gang.</span>
            </label>
          </div>
          <div>
            <p className="font-medium">Forventet byggetid</p>
            <p className="text-sm text-muted-foreground">{formatDuration(pkg.expectedSeconds)}</p>
          </div>
          <div className="flex max-w-md items-start gap-2 text-sm text-muted-foreground">
            <Info className="mt-0.5 size-4 shrink-0" />
            {pkg.pinnable
              ? "Velg en cachet versjon for å låse den for alle profiler."
              : "Pakken følger revisjonen til hver profil (kjerner, drivere og moduler kan ikke låses enkeltvis)."}
          </div>
        </CardContent>
      </Card>
      <div className="space-y-4">
        {pkg.versions.map((version, index) => (
          <VersionCard key={version.id} pkg={pkg} version={version} newest={index === 0} />
        ))}
      </div>
    </div>
  );
}

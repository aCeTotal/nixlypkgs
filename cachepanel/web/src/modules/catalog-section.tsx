import { Lock } from "lucide-react";
import { Badge } from "@/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import type { CatalogModule } from "./queries";
import { SourceDialog } from "./source-dialog";

function UsedBy({ module }: { module: CatalogModule }) {
  if (module.automatic) return <span className="text-xs text-muted-foreground">Velges av maskinvaren</span>;
  if (module.required) return <span className="text-xs text-muted-foreground">Alle profiler</span>;
  if (module.usedBy.length === 0) return <span className="text-xs text-muted-foreground">Ingen profiler</span>;
  return (
    <div className="flex flex-wrap justify-end gap-1">
      {module.usedBy.map((profile) => (
        <Badge key={profile} variant="secondary">
          {profile}
        </Badge>
      ))}
    </div>
  );
}

// One category of repository modules.
export function CatalogSection({ title, modules }: { title: string; modules: CatalogModule[] }) {
  return (
    <Card className="gap-3">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{modules.length} moduler</CardDescription>
      </CardHeader>
      <CardContent className="divide-y">
        {modules.map((module) => (
          <div key={module.name} className={`flex items-center gap-3 py-2 ${module.present ? "" : "opacity-60"}`}>
            <div className="min-w-0 flex-1">
              <p className="flex flex-wrap items-center gap-1.5 text-sm font-medium">
                {module.title}
                {module.required && (
                  <Badge variant="secondary" className="gap-1">
                    <Lock className="size-3" />
                    Påkrevd
                  </Badge>
                )}
                {module.x86Only && <Badge variant="outline">x86</Badge>}
                {!module.present && <Badge variant="destructive">Fjernet</Badge>}
              </p>
              <p className="truncate font-mono text-xs text-muted-foreground">{module.path}</p>
            </div>
            <UsedBy module={module} />
            <SourceDialog module={module} />
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

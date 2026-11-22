import { useSuspenseQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { timeAgo } from "@/format/time";
import { PageHeader } from "@/shell/page-header";
import { Badge } from "@/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/ui/tabs";
import { CatalogSection } from "./catalog-section";
import { NewModuleDialog } from "./new-module-dialog";
import { catalogQuery, modulesQuery } from "./queries";

export function ModulesPage() {
  const { data: modules } = useSuspenseQuery(modulesQuery);
  const { data: catalog } = useSuspenseQuery(catalogQuery);
  const sections = catalog.categories
    .map((category) => ({ ...category, modules: catalog.modules.filter((module) => module.category === category.name) }))
    .filter((section) => section.modules.length > 0);
  return (
    <div className="space-y-4">
      <PageHeader
        title="Moduler"
        description="Registeret over alt en maskin kan få: modulene i nixlypkgs sortert etter kategori, og egne panelmoduler."
        actions={<NewModuleDialog />}
      />
      <Tabs defaultValue="catalog">
        <TabsList>
          <TabsTrigger value="catalog">nixlypkgs ({catalog.modules.length})</TabsTrigger>
          <TabsTrigger value="panel">Panelmoduler ({modules.length})</TabsTrigger>
        </TabsList>
        <TabsContent value="catalog" className="pt-4">
          <div className="grid gap-4 xl:grid-cols-2">
            {sections.map((section) => (
              <CatalogSection key={section.name} title={section.title} modules={section.modules} />
            ))}
          </div>
        </TabsContent>
        <TabsContent value="panel" className="pt-4">
          <div className="overflow-hidden rounded-xl border bg-card">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Modul</TableHead>
                  <TableHead>Brukes av</TableHead>
                  <TableHead className="text-right">Linjer</TableHead>
                  <TableHead className="text-right">Revisjon</TableHead>
                  <TableHead className="text-right">Endret</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {modules.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={5} className="py-8 text-center text-sm text-muted-foreground">
                      Ingen panelmoduler ennå. Lag en for å teste nye ting på en profil.
                    </TableCell>
                  </TableRow>
                )}
                {modules.map((module) => (
                  <TableRow key={module.id}>
                    <TableCell>
                      <Link to="/modules/$id" params={{ id: String(module.id) }} className="font-medium hover:text-primary hover:underline">
                        {module.title}
                      </Link>
                      <p className="font-mono text-xs text-muted-foreground">{module.slug}.nix</p>
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {module.usedBy.length === 0 && <span className="text-sm text-muted-foreground">Ingen profiler</span>}
                        {module.usedBy.map((profile) => (
                          <Badge key={profile} variant="secondary">
                            {profile}
                          </Badge>
                        ))}
                      </div>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{module.lines}</TableCell>
                    <TableCell className="text-right tabular-nums">{module.revision}</TableCell>
                    <TableCell className="text-right text-sm text-muted-foreground">{timeAgo(module.updatedAt)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}

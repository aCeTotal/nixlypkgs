import { useSuspenseQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { PackagePlus } from "lucide-react";
import { timeAgo } from "@/format/time";
import { PageHeader } from "@/shell/page-header";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/ui/table";
import { builderLabels, recipesQuery, type RecipeSummary } from "./queries";
import { RecipeStateBadge } from "./state-badge";

const originLabels: Record<RecipeSummary["origin"]["origin"], string> = {
  aur: "AUR",
  arch: "Arch Linux",
  pkgbuild: "PKGBUILD",
  url: "Lenke",
  upload: "Opplastet fil",
  github: "GitHub",
};

function originOf({ origin }: RecipeSummary) {
  const detail = origin.name || origin.url || origin.files?.join(", ");
  return `${originLabels[origin.origin]}${detail ? ` · ${detail}` : ""}`;
}

export function RecipesPage() {
  const { data: recipes } = useSuspenseQuery(recipesQuery);
  return (
    <div className="space-y-4">
      <PageHeader
        title="Nye pakker"
        description="Pakker til nixlypkgs fra en lenke, en fil, GitHub eller en PKGBUILD fra Arch og AUR."
        actions={
          <Button asChild>
            <Link to="/recipes/new">
              <PackagePlus />
              Ny pakke
            </Link>
          </Button>
        }
      />
      <div className="overflow-hidden rounded-xl border bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Pakke</TableHead>
              <TableHead>Kilde</TableHead>
              <TableHead>Byggemåte</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Endret</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {recipes.length === 0 && (
              <TableRow>
                <TableCell colSpan={5} className="py-10 text-center text-sm text-muted-foreground">
                  Ingen pakker under arbeid. Start med «Ny pakke».
                </TableCell>
              </TableRow>
            )}
            {recipes.map((recipe) => (
              <TableRow key={recipe.id}>
                <TableCell>
                  <Link to="/recipes/$id" params={{ id: String(recipe.id) }} className="font-medium hover:text-primary hover:underline">
                    {recipe.attr ?? "Analyserer …"}
                  </Link>
                  {recipe.version && <span className="ml-2 font-mono text-xs text-muted-foreground">{recipe.version}</span>}
                  {recipe.description && <p className="max-w-md truncate text-xs text-muted-foreground">{recipe.description}</p>}
                </TableCell>
                <TableCell className="max-w-xs truncate text-sm text-muted-foreground">{originOf(recipe)}</TableCell>
                <TableCell>{recipe.builder && <Badge variant="outline">{builderLabels[recipe.builder]}</Badge>}</TableCell>
                <TableCell>
                  <RecipeStateBadge state={recipe.state} />
                </TableCell>
                <TableCell className="text-right text-sm text-muted-foreground">{timeAgo(recipe.updatedAt)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}

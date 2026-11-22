import { Info, X } from "lucide-react";
import { AttrSearch } from "@/nixpkgs/attr-search";
import { Button } from "@/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import type { ProfileSettings } from "./queries";

type ProfilePackagesProps = { packages: string[]; update: (change: Partial<ProfileSettings>) => void };

export function ProfilePackages({ packages, update }: ProfilePackagesProps) {
  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_22rem]">
      <Card>
        <CardHeader>
          <CardTitle>Pakker</CardTitle>
          <CardDescription>Installeres i systemet i tillegg til det modulene tar med.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <AttrSearch
            label="Søk etter pakke"
            placeholder="Søk, f.eks. blender eller python3Packages.numpy"
            exclude={packages}
            onPick={(attr) => update({ packages: [...packages, attr] })}
          />
          {packages.length === 0 ? (
            <p className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">
              Ingen ekstra pakker – profilen får det modulene installerer.
            </p>
          ) : (
            <ul className="flex flex-wrap gap-2">
              {packages.map((attr) => (
                <li key={attr} className="flex items-center gap-1 rounded-lg border bg-muted/40 py-1 pr-1 pl-3 font-mono text-sm">
                  {attr}
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label={`Fjern ${attr}`}
                    onClick={() => update({ packages: packages.filter((pkg) => pkg !== attr) })}
                  >
                    <X />
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
      <Card className="h-fit bg-muted/30">
        <CardContent className="space-y-3 text-sm text-muted-foreground">
          <p className="flex items-center gap-2 font-medium text-foreground">
            <Info className="size-4 text-primary" />
            Alltid stable
          </p>
          <p>
            Pakkene kommer fra nixpkgs stable med nixlypkgs på toppen – det samme som cachen bygger. nixlypkgs-pakkene har
            de tre siste versjonene i cachen; profilen følger revisjonen under Innstillinger.
          </p>
          <p>Mangler et program, lag det under nixlypkgs → Ny pakke.</p>
        </CardContent>
      </Card>
    </div>
  );
}

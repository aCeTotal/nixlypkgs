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
          <CardTitle>Packages</CardTitle>
          <CardDescription>Installed system-wide on top of what the modules bring.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <AttrSearch
            label="Search for a package"
            placeholder="Search, e.g. blender or python3Packages.numpy"
            exclude={packages}
            onPick={(attr) => update({ packages: [...packages, attr] })}
          />
          {packages.length === 0 ? (
            <p className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">
              No extra packages – the profile gets what its modules install.
            </p>
          ) : (
            <ul className="flex flex-wrap gap-2">
              {packages.map((attr) => (
                <li key={attr} className="flex items-center gap-1 rounded-lg border bg-muted/40 py-1 pr-1 pl-3 font-mono text-sm">
                  {attr}
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label={`Remove ${attr}`}
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
            Always stable
          </p>
          <p>
            Packages come from nixpkgs stable with nixlypkgs on top – exactly what the cache builds. nixlypkgs derivations
            keep their three newest versions in the cache; the profile follows the revision under Settings.
          </p>
          <p>Missing a program? Add it under nixlypkgs → Add derivation.</p>
        </CardContent>
      </Card>
    </div>
  );
}

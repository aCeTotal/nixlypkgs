import { useMutation } from "@tanstack/react-query";
import { GitCommitVertical, Rocket } from "lucide-react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { FileBrowser } from "@/shell/file-browser";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { DeployKey } from "./deploy-key";
import { publishRecipe, type RecipeDetail } from "./queries";

const flow = [
  "Commit til pkgs/<attr> i nixlypkgs",
  "Panelet evaluerer og bygger den",
  "De tre siste versjonene ligger i cachen",
  "Legg pakken til en profil under Pakker",
];

export function RecipePublish({ recipe, dirty }: { recipe: RecipeDetail; dirty: boolean }) {
  const publish = useMutation({
    mutationFn: () => publishRecipe(recipe.id),
    onSuccess: ({ sha }) => toast.success(`Publisert som ${shortSha(sha)}`),
  });
  const tested = recipe.state === "ready" || recipe.state === "published";
  const files = recipe.files.map((file) => ({ path: file.name, content: file.text || `(binærfil, ${file.size} byte)` }));
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Publiser til nixlypkgs</CardTitle>
          <CardDescription>
              {tested ? "Testbygget gikk gjennom. Publiser når du er fornøyd." : "Publisering åpnes når et testbygg har gått gjennom."}
            </CardDescription>
          <CardAction>
            <Button onClick={() => publish.mutate()} disabled={!tested || dirty || publish.isPending}>
            <Rocket />
            {recipe.state === "published" ? "Publiser på nytt" : "Publiser"}
          </Button>
          </CardAction>
        </CardHeader>
        <CardContent className="space-y-3">
          <ol className="grid gap-2 text-sm sm:grid-cols-4">
            {flow.map((step, index) => (
              <li key={step} className="rounded-lg bg-muted/50 px-3 py-2">
                <span className="mr-1.5 font-mono text-xs text-primary">{index + 1}</span>
                {step}
              </li>
            ))}
          </ol>
          {recipe.publishedSha && (
            <p className="flex items-center gap-2 text-sm text-muted-foreground">
              <GitCommitVertical className="size-4" />
              Siste publisering: <span className="font-mono text-foreground">{shortSha(recipe.publishedSha)}</span>
            </p>
          )}
        </CardContent>
      </Card>
      <DeployKey />
      <FileBrowser files={files} />
    </div>
  );
}

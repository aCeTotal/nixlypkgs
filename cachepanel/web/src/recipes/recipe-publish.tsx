import { useMutation } from "@tanstack/react-query";
import { GitCommitVertical, Rocket } from "lucide-react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { FileBrowser } from "@/shell/file-browser";
import { CommitButton } from "@/source/commit-button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { publishRecipe, type RecipeDetail } from "./queries";

const flow = [
  "Commit to pkgs/<attr> in nixlypkgs",
  "The panel evaluates and builds it",
  "Its three newest versions stay in the cache",
  "Add it to a profile under Packages",
];

export function RecipePublish({ recipe, dirty }: { recipe: RecipeDetail; dirty: boolean }) {
  const publish = useMutation({
    mutationFn: (message: string) => publishRecipe(recipe.id, message),
    onSuccess: ({ sha }) => toast.success(`Published as ${shortSha(sha)}`),
  });
  const tested = recipe.state === "ready" || recipe.state === "published";
  const files = recipe.files.map((file) => ({ path: file.name, content: file.text || `(binary file, ${file.size} bytes)` }));
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Publish to nixlypkgs</CardTitle>
          <CardDescription>
              {tested ? "The test build passed. Publish when you are happy." : "Publishing opens once a test build has passed."}
            </CardDescription>
          <CardAction>
            <CommitButton
              icon={Rocket}
              title={`Publish ${recipe.spec?.attr ?? "the recipe"}`}
              label={recipe.state === "published" ? "Publish again" : "Publish"}
              suggestion={`${recipe.spec?.attr ?? "recipe"}: ${recipe.spec?.version ?? "new"}`}
              pending={publish.isPending}
              disabled={!tested || dirty}
              onCommit={(message) => publish.mutate(message)}
            />
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
              Last published: <span className="font-mono text-foreground">{shortSha(recipe.publishedSha)}</span>
            </p>
          )}
        </CardContent>
      </Card>
      <FileBrowser files={files} />
    </div>
  );
}

import { useMutation } from "@tanstack/react-query";
import { CircleCheck, Hammer, Lightbulb, Square, Wrench } from "lucide-react";
import { Alert, AlertDescription, AlertTitle } from "@/ui/alert";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { recipeAction, type RecipeDetail } from "./queries";
import { RecipeLog } from "./recipe-log";

export function RecipeBuild({ recipe, dirty }: { recipe: RecipeDetail; dirty: boolean }) {
  const act = useMutation({ mutationFn: (action: "build" | "stop") => recipeAction(recipe.id, action) });
  const building = recipe.state === "building";
  const steps = recipe.report.steps ?? [];
  const hints = recipe.report.hints ?? [];
  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_24rem]">
      <Card>
        <CardHeader>
          <CardTitle>Testbygg</CardTitle>
          <CardDescription>Bygger mot nixpkgs stable i sandkasse. Feil loggen forklarer, rettes automatisk og bygges på nytt.</CardDescription>
          <CardAction>
            {building ? (
            <Button variant="outline" onClick={() => act.mutate("stop")}>
              <Square />
              Stopp
            </Button>
          ) : (
            <Button onClick={() => act.mutate("build")} disabled={dirty || act.isPending}>
              <Hammer />
              {dirty ? "Lagre først" : "Testbygg"}
            </Button>
          )}
          </CardAction>
        </CardHeader>
        <CardContent>
          <RecipeLog id={recipe.id} live={building} />
        </CardContent>
      </Card>
      <div className="space-y-4">
        {recipe.state === "ready" && recipe.output && (
          <Alert>
            <CircleCheck className="text-success" />
            <AlertTitle>Bygget uten feil</AlertTitle>
            <AlertDescription className="font-mono text-xs break-all">{recipe.output}</AlertDescription>
          </Alert>
        )}
        {recipe.state === "failed" && recipe.error && (
          <Alert variant="destructive">
            <AlertTitle>Bygget feilet</AlertTitle>
            <AlertDescription>{recipe.error}</AlertDescription>
          </Alert>
        )}
        {hints.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Lightbulb className="size-4 text-warning" />
                Dette må du se på
              </CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="space-y-2 text-sm">
                {hints.map((hint) => (
                  <li key={hint}>{hint}</li>
                ))}
              </ul>
            </CardContent>
          </Card>
        )}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Wrench className="size-4 text-primary" />
              Rettet automatisk
            </CardTitle>
            <CardDescription>{steps.length === 0 ? "Ingenting å rette ennå." : `${steps.length} rettelser i siste testbygg.`}</CardDescription>
          </CardHeader>
          {steps.length > 0 && (
            <CardContent>
              <ol className="space-y-1.5 text-sm">
                {steps.map((step) => (
                  <li key={step} className="flex gap-2">
                    <CircleCheck className="mt-0.5 size-3.5 shrink-0 text-success" />
                    <span>{step}</span>
                  </li>
                ))}
              </ol>
            </CardContent>
          )}
        </Card>
      </div>
    </div>
  );
}

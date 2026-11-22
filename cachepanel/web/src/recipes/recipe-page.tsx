import { useMutation, useSuspenseQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { ArrowLeft, Info, Save, ScanSearch, Trash2, Undo2 } from "lucide-react";
import { useState } from "react";
import { ConfirmButton } from "@/shell/confirm-button";
import { PageHeader } from "@/shell/page-header";
import { Alert, AlertDescription, AlertTitle } from "@/ui/alert";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Card, CardContent } from "@/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/ui/tabs";
import { builderLabels, deleteRecipe, recipeQuery, saveRecipe, type RecipeDetail, type Spec } from "./queries";
import { RecipeBuild } from "./recipe-build";
import { RecipeDeps } from "./recipe-deps";
import { RecipePublish } from "./recipe-publish";
import { RecipeSetup } from "./recipe-setup";
import { RecipeStateBadge } from "./state-badge";

const route = getRouteApi("/app/recipes/$id");

const analysis = ["Henter kilden", "Pakker ut i sandkasse", "Finner byggemåte og metadata", "Slår opp avhengigheter i nixpkgs"];

export function RecipePage() {
  const { id } = route.useParams();
  const { data } = useSuspenseQuery(recipeQuery(Number(id)));
  return (
    <div className="space-y-5 pb-20">
      <Button asChild variant="ghost" size="sm" className="-ml-2">
        <Link to="/recipes">
          <ArrowLeft />
          Nye pakker
        </Link>
      </Button>
      {data.spec ? <RecipeEditor key={JSON.stringify(data.spec)} recipe={data} spec={data.spec} /> : <Unanalysed recipe={data} />}
    </div>
  );
}

function RemoveButton({ recipe }: { recipe: RecipeDetail }) {
  const navigate = route.useNavigate();
  const remove = useMutation({ mutationFn: () => deleteRecipe(recipe.id), onSuccess: () => navigate({ to: "/recipes" }) });
  return (
    <ConfirmButton
      label="Slett"
      icon={Trash2}
      title="Slette oppskriften?"
      description="Oppskriften og testbyggene forsvinner fra panelet. En publisert pakke blir liggende i nixlypkgs."
      onConfirm={() => remove.mutate()}
    />
  );
}

function Unanalysed({ recipe }: { recipe: RecipeDetail }) {
  if (recipe.state === "importing") {
    return (
      <Card className="mx-auto max-w-xl overflow-hidden">
        <CardContent className="space-y-5 py-8 text-center">
          <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-gradient-to-br from-primary/25 to-chart-5/20 text-primary">
            <ScanSearch className="size-7 animate-pulse" />
          </span>
          <div>
            <h2 className="text-lg font-semibold">Analyserer kilden</h2>
            <p className="text-sm text-muted-foreground">Store kilder kan ta et par minutter.</p>
          </div>
          <ol className="mx-auto w-fit space-y-2 text-left text-sm text-muted-foreground">
            {analysis.map((step) => (
              <li key={step} className="flex items-center gap-2">
                <span className="size-1.5 animate-pulse rounded-full bg-primary" />
                {step}
              </li>
            ))}
          </ol>
        </CardContent>
      </Card>
    );
  }
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <Alert variant="destructive">
        <AlertTitle>Fikk ikke analysert kilden</AlertTitle>
        <AlertDescription className="whitespace-pre-wrap">{recipe.error}</AlertDescription>
      </Alert>
      <div className="flex gap-2">
        <Button asChild>
          <Link to="/recipes/new">Prøv en annen kilde</Link>
        </Button>
        <RemoveButton recipe={recipe} />
      </div>
    </div>
  );
}

// Edits stay local until saved.
function RecipeEditor({ recipe, spec: saved }: { recipe: RecipeDetail; spec: Spec }) {
  const [spec, setSpec] = useState(saved);
  const dirty = JSON.stringify(spec) !== JSON.stringify(saved);
  const save = useMutation({ mutationFn: () => saveRecipe(recipe.id, { spec }) });
  const update = (change: Partial<Spec>) => setSpec((current) => ({ ...current, ...change }));
  const notes = recipe.report.notes ?? [];
  return (
    <>
      <PageHeader
        title={
          <span className="flex flex-wrap items-center gap-2">
            {saved.attr}
            <span className="font-mono text-base font-normal text-muted-foreground">{saved.version}</span>
          </span>
        }
        description={
          <span className="flex flex-wrap items-center gap-2">
            <RecipeStateBadge state={recipe.state} />
            <Badge variant="outline">{builderLabels[saved.builder]}</Badge>
          </span>
        }
        actions={<RemoveButton recipe={recipe} />}
      />
      {notes.length > 0 && (
        <Alert>
          <Info className="text-primary" />
          <AlertTitle>Fra analysen</AlertTitle>
          <AlertDescription>
            <ul className="list-disc space-y-1 pl-4">
              {notes.map((note) => (
                <li key={note}>{note}</li>
              ))}
            </ul>
          </AlertDescription>
        </Alert>
      )}
      <Tabs defaultValue={recipe.state === "draft" ? "setup" : "build"}>
        <TabsList>
          <TabsTrigger value="setup">1 · Oppsett</TabsTrigger>
          <TabsTrigger value="deps">2 · Avhengigheter</TabsTrigger>
          <TabsTrigger value="build">3 · Testbygg</TabsTrigger>
          <TabsTrigger value="publish">4 · Publiser</TabsTrigger>
        </TabsList>
        <TabsContent value="setup" className="pt-4">
          <RecipeSetup spec={spec} update={update} />
        </TabsContent>
        <TabsContent value="deps" className="pt-4">
          <RecipeDeps spec={spec} update={update} />
        </TabsContent>
        <TabsContent value="build" className="pt-4">
          <RecipeBuild recipe={recipe} dirty={dirty} />
        </TabsContent>
        <TabsContent value="publish" className="pt-4">
          <RecipePublish recipe={recipe} dirty={dirty} />
        </TabsContent>
      </Tabs>
      {dirty && (
        <div className="fixed inset-x-0 bottom-0 z-30 flex justify-center p-4">
          <div className="flex items-center gap-3 rounded-xl border bg-popover/95 px-4 py-3 shadow-xl backdrop-blur animate-in slide-in-from-bottom-4">
            <span className="text-sm">{save.error ? save.error.message : "Ulagrede endringer – testbygg på nytt etterpå."}</span>
            <Button variant="ghost" size="sm" onClick={() => setSpec(saved)}>
              <Undo2 />
              Forkast
            </Button>
            <Button size="sm" onClick={() => save.mutate()} disabled={save.isPending}>
              <Save />
              Lagre
            </Button>
          </div>
        </div>
      )}
    </>
  );
}

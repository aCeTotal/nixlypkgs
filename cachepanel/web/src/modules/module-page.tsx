import { useMutation, useSuspenseQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { ArrowLeft, CircleCheck, CircleX, History, Save, Trash2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { dateTime, timeAgo } from "@/format/time";
import { ConfirmButton } from "@/shell/confirm-button";
import { PageHeader } from "@/shell/page-header";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/ui/card";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Spinner } from "@/ui/spinner";
import { NixEditor } from "./nix-editor";
import { deleteModule, moduleQuery, revisionSource, saveModule, type ModuleDetail, type ModuleDraft } from "./queries";
import { useSyntaxCheck } from "./use-syntax-check";

const route = getRouteApi("/app/modules/$id");

export function ModulePage() {
  const { id } = route.useParams();
  const { data } = useSuspenseQuery(moduleQuery(Number(id)));
  return <ModuleEditor key={`${data.id}-${data.revision}-${data.updatedAt}`} module={data} />;
}

function ModuleEditor({ module }: { module: ModuleDetail }) {
  const navigate = route.useNavigate();
  const initial: ModuleDraft = { slug: module.slug, title: module.title, description: module.description, source: module.source };
  const [draft, setDraft] = useState(initial);
  const syntax = useSyntaxCheck(draft.source);
  const dirty = JSON.stringify(draft) !== JSON.stringify(initial);
  const save = useMutation({ mutationFn: () => saveModule(module.id, draft), onSuccess: () => toast.success("Lagret – berørte profiler testes nå") });
  const remove = useMutation({ mutationFn: () => deleteModule(module.id), onSuccess: () => navigate({ to: "/modules" }) });
  const restore = useMutation({
    mutationFn: (revision: number) => revisionSource(module.id, revision),
    onSuccess: ({ source }) => setDraft((current) => ({ ...current, source })),
  });
  return (
    <div className="space-y-5">
      <Button asChild variant="ghost" size="sm" className="-ml-2">
        <Link to="/modules">
          <ArrowLeft />
          Modulregister
        </Link>
      </Button>
      <PageHeader
        title={module.title}
        description={
          <span className="flex flex-wrap items-center gap-2">
            <span className="font-mono">{module.slug}.nix</span>· revisjon {module.revision} · endret {timeAgo(module.updatedAt)}
            {module.usedBy.map((profile) => (
              <Badge key={profile} variant="secondary">
                {profile}
              </Badge>
            ))}
          </span>
        }
        actions={
          <>
            <ConfirmButton
              label="Slett"
              icon={Trash2}
              title={`Slette ${module.title}?`}
              description="Moduler som brukes av en profil kan ikke slettes – fjern den fra profilene først."
              onConfirm={() => remove.mutate()}
              disabled={module.usedBy.length > 0}
            />
            <Button onClick={() => save.mutate()} disabled={!dirty || syntax.error !== "" || save.isPending}>
              <Save />
              Lagre
            </Button>
          </>
        }
      />
      <div className="grid gap-4 xl:grid-cols-[1fr_20rem]">
        <div className="space-y-3">
          <div className="h-[60vh]">
            <NixEditor value={draft.source} onChange={(source) => setDraft((current) => ({ ...current, source }))} />
          </div>
          <SyntaxStatus checking={syntax.checking} error={syntax.error} />
        </div>
        <div className="space-y-4">
          <Card>
            <CardContent>
              <FieldGroup>
                <Field>
                  <FieldLabel htmlFor="module-title">Tittel</FieldLabel>
                  <Input id="module-title" value={draft.title} onChange={(event) => setDraft({ ...draft, title: event.target.value })} />
                </Field>
                <Field>
                  <FieldLabel htmlFor="module-slug">Filnavn</FieldLabel>
                  <Input id="module-slug" className="font-mono" value={draft.slug} onChange={(event) => setDraft({ ...draft, slug: event.target.value })} />
                </Field>
                <Field>
                  <FieldLabel htmlFor="module-description">Beskrivelse</FieldLabel>
                  <Input
                    id="module-description"
                    value={draft.description}
                    onChange={(event) => setDraft({ ...draft, description: event.target.value })}
                  />
                </Field>
              </FieldGroup>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <History className="size-4" />
                Revisjoner
              </CardTitle>
            </CardHeader>
            <CardContent className="max-h-80 space-y-1 overflow-auto">
              {module.revisions.map((revision) => (
                <button
                  key={revision.revision}
                  type="button"
                  onClick={() => restore.mutate(revision.revision)}
                  className="flex w-full items-center justify-between rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted"
                >
                  <span>Revisjon {revision.revision}</span>
                  <span className="text-xs text-muted-foreground">{dateTime(revision.createdAt)}</span>
                </button>
              ))}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}

function SyntaxStatus({ checking, error }: { checking: boolean; error: string }) {
  if (checking) return <p className="flex items-center gap-2 text-sm text-muted-foreground"><Spinner className="size-3.5" /> Sjekker syntaks…</p>;
  if (!error) return <p className="flex items-center gap-2 text-sm text-success"><CircleCheck className="size-4" /> Gyldig Nix</p>;
  return (
    <div className="space-y-1">
      <p className="flex items-center gap-2 text-sm text-destructive">
        <CircleX className="size-4" /> Syntaksfeil
      </p>
      <pre className="overflow-auto rounded-lg bg-danger-soft p-3 font-mono text-xs whitespace-pre-wrap text-destructive">{error}</pre>
    </div>
  );
}

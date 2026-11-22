import { useMutation, useSuspenseQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { ArrowLeft, CircleCheck, CircleX, History, ListTree, Lock, Save, Trash2 } from "lucide-react";
import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { dateTime, timeAgo } from "@/format/time";
import { CheckBadge } from "@/profiles/check-badge";
import { ConfirmButton } from "@/shell/confirm-button";
import { PageHeader } from "@/shell/page-header";
import { Badge } from "@/ui/badge";
import { Button } from "@/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/ui/card";
import { Field, FieldContent, FieldDescription, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Spinner } from "@/ui/spinner";
import { Switch } from "@/ui/switch";
import { ModuleOutline } from "./module-outline";
import { NixEditor, type NixEditorHandle } from "./nix-editor";
import { activePath, outline, type OutlineItem } from "./outline";
import { deleteModule, moduleQuery, revisionSource, saveModule, type ModuleDetail, type ModuleDraft } from "./queries";
import { useSyntaxCheck, type SyntaxState } from "./use-syntax-check";

const route = getRouteApi("/app/modules/$id");

export function ModulePage() {
  const { id } = route.useParams();
  const { data } = useSuspenseQuery(moduleQuery(Number(id)));
  return <ModuleEditor key={data.id} module={data} />;
}

function draftOf(module: ModuleDetail): ModuleDraft {
  return { slug: module.slug, title: module.title, description: module.description, source: module.source, required: module.required };
}

function ModuleEditor({ module }: { module: ModuleDetail }) {
  const navigate = route.useNavigate();
  const editor = useRef<NixEditorHandle>(null);
  const initial = useMemo(() => draftOf(module), [module]);
  const [draft, setDraft] = useState(initial);
  const [base, setBase] = useState(initial);
  // Server updates replace untouched drafts.
  if (base !== initial) {
    setBase(initial);
    if (JSON.stringify(draft) === JSON.stringify(base)) setDraft(initial);
  }
  const [cursor, setCursor] = useState(0);
  const syntax = useSyntaxCheck(draft.source);
  const deferred = useDeferredValue(draft.source);
  const items = useMemo(() => outline(deferred), [deferred]);
  const dirty = JSON.stringify(draft) !== JSON.stringify(initial);
  const valid = syntax.problem.error === "";
  const save = useMutation({
    mutationFn: () => saveModule(module.id, draft),
    onSuccess: () => toast.success("Lagret – profilene som bruker modulen testes nå"),
  });
  const remove = useMutation({ mutationFn: () => deleteModule(module.id), onSuccess: () => navigate({ to: "/modules" }) });
  const restore = useMutation({
    mutationFn: (revision: number) => revisionSource(module.id, revision),
    onSuccess: ({ source }) => setDraft((current) => ({ ...current, source })),
  });
  const trySave = () => {
    if (dirty && valid && !save.isPending) save.mutate();
  };

  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  const jump = (item: OutlineItem) => editor.current?.jumpTo(item.from);
  return (
    <div className="space-y-4">
      <Button asChild variant="ghost" size="sm" className="-ml-2">
        <Link to="/modules">
          <ArrowLeft />
          Alle moduler
        </Link>
      </Button>
      <PageHeader
        title={module.title}
        description={
          <span className="flex flex-wrap items-center gap-2">
            <span className="font-mono">{module.slug}.nix</span>· revisjon {module.revision} · endret {timeAgo(module.updatedAt)}
            {module.required && (
              <Badge variant="secondary" className="gap-1">
                <Lock className="size-3" />
                Påkrevd i alle profiler
              </Badge>
            )}
          </span>
        }
        actions={
          <>
            <ConfirmButton
              label="Slett"
              icon={Trash2}
              title={`Slette ${module.title}?`}
              description="Bare moduler som ingen profil bruker kan slettes."
              onConfirm={() => remove.mutate()}
              disabled={module.required || module.usedBy.length > 0}
            />
            <Button onClick={trySave} disabled={!dirty || !valid || save.isPending}>
              <Save />
              Lagre
            </Button>
          </>
        }
      />
      <div className="grid gap-4 lg:grid-cols-[16rem_minmax(0,1fr)] 2xl:grid-cols-[17rem_minmax(0,1fr)_19rem]">
        <Card className="gap-3 py-4 lg:h-[calc(100dvh-15rem)] lg:min-h-[32rem]">
          <CardHeader className="px-4">
            <CardTitle className="flex items-center gap-2 text-sm">
              <ListTree className="size-4 text-primary" />
              Disposisjon
            </CardTitle>
          </CardHeader>
          <CardContent className="min-h-0 flex-1 px-3">
            <ModuleOutline items={items} active={activePath(items, cursor)} onSelect={jump} />
          </CardContent>
        </Card>
        <div className="flex min-w-0 flex-col gap-2">
          <div className="h-[70vh] lg:h-[calc(100dvh-17.5rem)] lg:min-h-[30rem]">
            <NixEditor
              ref={editor}
              value={draft.source}
              problem={syntax.problem}
              onChange={(source) => setDraft((current) => ({ ...current, source }))}
              onCursor={setCursor}
              onSave={trySave}
            />
          </div>
          <StatusBar syntax={syntax} dirty={dirty} onJump={(line) => editor.current?.jumpTo(lineStart(draft.source, line))} />
        </div>
        <div className="space-y-4 lg:col-span-2 2xl:col-span-1">
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
                <Field orientation="horizontal">
                  <Switch id="module-required" checked={draft.required} onCheckedChange={(required) => setDraft({ ...draft, required })} />
                  <FieldContent>
                    <FieldLabel htmlFor="module-required">Påkrevd</FieldLabel>
                    <FieldDescription>Med i alle profiler, kan ikke velges bort.</FieldDescription>
                  </FieldContent>
                </Field>
              </FieldGroup>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>Brukes av</CardTitle>
            </CardHeader>
            <CardContent className="space-y-1">
              {module.usedBy.length === 0 && <p className="text-sm text-muted-foreground">Ingen profiler ennå.</p>}
              {module.usedBy.map((profile) => (
                <Link
                  key={profile.name}
                  to="/profiles/$name"
                  params={{ name: profile.name }}
                  className="flex items-center justify-between gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-muted"
                >
                  <span className="font-medium">{profile.title}</span>
                  <CheckBadge state={profile.checkState} />
                </Link>
              ))}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <History className="size-4" />
                Revisjoner
              </CardTitle>
            </CardHeader>
            <CardContent className="max-h-72 space-y-1 overflow-auto">
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

function lineStart(source: string, line: number) {
  let pos = 0;
  for (let current = 1; current < line; current++) pos = source.indexOf("\n", pos) + 1;
  return pos;
}

function StatusBar({ syntax, dirty, onJump }: { syntax: SyntaxState; dirty: boolean; onJump: (line: number) => void }) {
  const { problem } = syntax;
  return (
    <div className="flex min-h-7 flex-wrap items-center gap-x-4 gap-y-1 px-1 text-xs text-muted-foreground">
      {syntax.checking && (
        <span className="flex items-center gap-1.5">
          <Spinner className="size-3.5" /> Sjekker syntaks…
        </span>
      )}
      {!syntax.checking && problem.error === "" && (
        <span className="flex items-center gap-1.5 text-success">
          <CircleCheck className="size-3.5" /> Gyldig Nix
        </span>
      )}
      {!syntax.checking && problem.error !== "" && (
        <button type="button" onClick={() => problem.line && onJump(problem.line)} className="flex items-center gap-1.5 text-destructive hover:underline">
          <CircleX className="size-3.5" />
          Syntaksfeil{problem.line ? ` på linje ${problem.line}` : ""}
        </button>
      )}
      <span>{dirty ? "Ulagrede endringer" : "Lagret"}</span>
      <span className="ml-auto hidden sm:inline">Ctrl+S lagrer · Ctrl+F søker · Ctrl+Shift+[ bretter</span>
    </div>
  );
}

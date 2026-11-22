import { CircleCheck, CircleDashed, GitBranch } from "lucide-react";
import { Badge } from "@/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/ui/select";
import { Textarea } from "@/ui/textarea";
import { builderLabels, type Builder, type Source, type Spec } from "./queries";

const noLicense = "none";

const licenses: Record<string, string> = {
  mit: "MIT",
  asl20: "Apache 2.0",
  bsd3: "BSD 3-clause",
  bsd2: "BSD 2-clause",
  gpl2Only: "GPL 2.0",
  gpl2Plus: "GPL 2.0 eller nyere",
  gpl3Only: "GPL 3.0",
  gpl3Plus: "GPL 3.0 eller nyere",
  lgpl21Only: "LGPL 2.1",
  lgpl21Plus: "LGPL 2.1 eller nyere",
  lgpl3Only: "LGPL 3.0",
  lgpl3Plus: "LGPL 3.0 eller nyere",
  agpl3Only: "AGPL 3.0",
  agpl3Plus: "AGPL 3.0 eller nyere",
  mpl20: "MPL 2.0",
  isc: "ISC",
  zlib: "zlib",
  unlicense: "Unlicense",
  cc0: "CC0",
  boost: "Boost",
  free: "Annen fri lisens",
  unfree: "Proprietær",
};

function describe(source: Source) {
  if (source.kind === "github") return `github:${source.owner}/${source.repo} @ ${source.rev}`;
  if (source.kind === "git") return `${source.url} @ ${source.rev}`;
  if (source.kind === "file") return `${source.name} (fil i oppskriften)`;
  return source.url ?? source.name;
}

type RecipeSetupProps = { spec: Spec; update: (change: Partial<Spec>) => void };

export function RecipeSetup({ spec, update }: RecipeSetupProps) {
  const meta = (change: Partial<Spec["meta"]>) => update({ meta: { ...spec.meta, ...change } });
  return (
    <div className="grid gap-4 xl:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Pakken</CardTitle>
          <CardDescription>Attributtet er navnet profiler og maskiner bruker.</CardDescription>
        </CardHeader>
        <CardContent>
          <FieldGroup>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field>
                <FieldLabel htmlFor="attr">Attributt</FieldLabel>
                <Input id="attr" className="font-mono" value={spec.attr} onChange={(event) => update({ attr: event.target.value })} />
              </Field>
              <Field>
                <FieldLabel htmlFor="pname">Navn</FieldLabel>
                <Input id="pname" className="font-mono" value={spec.pname} onChange={(event) => update({ pname: event.target.value })} />
              </Field>
              <Field>
                <FieldLabel htmlFor="version">Versjon</FieldLabel>
                <Input id="version" className="font-mono" value={spec.version} onChange={(event) => update({ version: event.target.value })} />
              </Field>
              <Field>
                <FieldLabel>Byggemåte</FieldLabel>
                <Select value={spec.builder} onValueChange={(value) => update({ builder: value as Builder })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {Object.entries(builderLabels).map(([value, label]) => (
                      <SelectItem key={value} value={value}>
                        {label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
            </div>
            <Field>
              <FieldLabel htmlFor="description">Beskrivelse</FieldLabel>
              <Textarea id="description" value={spec.meta.description} onChange={(event) => meta({ description: event.target.value })} />
            </Field>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field>
                <FieldLabel htmlFor="homepage">Hjemmeside</FieldLabel>
                <Input id="homepage" type="url" value={spec.meta.homepage} onChange={(event) => meta({ homepage: event.target.value })} />
              </Field>
              <Field>
                <FieldLabel htmlFor="program">Hovedprogram</FieldLabel>
                <Input id="program" className="font-mono" value={spec.meta.mainProgram} onChange={(event) => meta({ mainProgram: event.target.value })} />
                <FieldDescription>Fylles ut etter første vellykkede bygg.</FieldDescription>
              </Field>
            </div>
            <Field>
              <FieldLabel>Lisens</FieldLabel>
              <Select value={spec.meta.license || noLicense} onValueChange={(value) => meta({ license: value === noLicense ? "" : value })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={noLicense}>Ikke oppgitt</SelectItem>
                  {Object.entries(licenses).map(([value, label]) => (
                    <SelectItem key={value} value={value}>
                      {label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </FieldGroup>
        </CardContent>
      </Card>
      <Card className="h-fit">
        <CardHeader>
          <CardTitle>Kilder</CardTitle>
          <CardDescription>Låst med sjekksum. Mangler en, finner testbygget den.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {spec.sources.map((source) => (
            <div key={`${source.kind}-${source.name}-${source.url ?? source.repo}`} className="flex items-start gap-3 rounded-lg border p-3">
              {source.hash || source.kind === "file" ? (
                <CircleCheck className="mt-0.5 size-4 shrink-0 text-success" />
              ) : (
                <CircleDashed className="mt-0.5 size-4 shrink-0 text-warning" />
              )}
              <div className="min-w-0 flex-1">
                <p className="truncate font-mono text-xs">{describe(source)}</p>
                <p className="truncate font-mono text-[0.7rem] text-muted-foreground">{source.hash ?? "sjekksum hentes ved testbygg"}</p>
              </div>
              {source.history && (
                <Badge variant="outline" className="gap-1">
                  <GitBranch className="size-3" />
                  Med historikk
                </Badge>
              )}
            </div>
          ))}
          {spec.split && (
            <p className="pt-2 text-sm text-muted-foreground">
              Delt PKGBUILD – bygger <span className="font-mono text-foreground">package_{spec.split}</span>.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

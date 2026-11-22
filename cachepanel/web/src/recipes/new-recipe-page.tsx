import { useMutation } from "@tanstack/react-query";
import { Link, useNavigate } from "@tanstack/react-router";
import { ArrowLeft, FileCode, FolderGit2, Link2, Package, ScrollText, Upload, Wand2, type LucideIcon } from "lucide-react";
import { useState, type FormEvent } from "react";
import { PageHeader } from "@/shell/page-header";
import { Alert, AlertDescription } from "@/ui/alert";
import { Button } from "@/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Progress } from "@/ui/progress";
import { DropZone } from "./drop-zone";
import { importRecipe, uploadSource, type ImportRequest, type Origin } from "./queries";

type Choice = { origin: Origin; title: string; text: string; icon: LucideIcon };

const choices: Choice[] = [
  { origin: "url", title: "Lenke", text: "Kildekode, AppImage, .deb, .rpm, zip eller ferdig program fra en nettadresse.", icon: Link2 },
  { origin: "github", title: "GitHub", text: "Et repo, med siste utgivelse eller valgfri tag, gren eller commit.", icon: FolderGit2 },
  { origin: "upload", title: "Last opp fil", text: "Samme filtyper som en lenke, men fra din maskin. Panelet deler filen med maskinene.", icon: Upload },
  { origin: "aur", title: "AUR", text: "En pakke fra Arch User Repository. PKGBUILD-en kjøres som makepkg, men i Nix.", icon: Package },
  { origin: "arch", title: "Arch Linux", text: "En offisiell Arch-pakke, bygget fra Arch sin egen PKGBUILD.", icon: ScrollText },
  { origin: "pkgbuild", title: "PKGBUILD", text: "Last opp en PKGBUILD med patcher og andre lokale filer.", icon: FileCode },
];

// Base64 for JSON file bodies.
async function encode(file: File) {
  const bytes = new Uint8Array(await file.arrayBuffer());
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

export function NewRecipePage() {
  const navigate = useNavigate();
  const [origin, setOrigin] = useState<Origin>("url");
  const [text, setText] = useState("");
  const [ref, setRef] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [sent, setSent] = useState(0);
  const start = useMutation({
    mutationFn: async () => {
      const request: ImportRequest = { origin };
      if (origin === "url" || origin === "github") Object.assign(request, { url: text.trim(), ref: ref.trim() || undefined });
      if (origin === "aur" || origin === "arch") request.name = text.trim();
      if (origin === "upload") request.upload = (await uploadSource(files[0], setSent)).hash;
      if (origin === "pkgbuild") {
        const bodies = await Promise.all(files.map(async (file) => [file.name, await encode(file)] as const));
        request.files = Object.fromEntries(bodies);
      }
      return importRecipe(request);
    },
    onSuccess: (created) => navigate({ to: "/recipes/$id", params: { id: String(created.id) } }),
  });
  const choice = choices.find((item) => item.origin === origin) ?? choices[0];
  const ready = origin === "upload" || origin === "pkgbuild" ? files.length > 0 : text.trim() !== "";
  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (ready) start.mutate();
  };
  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm" className="-ml-2">
        <Link to="/recipes">
          <ArrowLeft />
          Nye pakker
        </Link>
      </Button>
      <PageHeader title="Ny pakke" description="Velg hvor programmet kommer fra. Resten finner veiviseren ut, og du kan justere alt før det publiseres." />
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {choices.map((item) => (
          <button
            key={item.origin}
            type="button"
            aria-label={item.title}
            aria-pressed={origin === item.origin}
            onClick={() => {
              setOrigin(item.origin);
              setFiles([]);
            }}
            className={cn(
              "group flex gap-3 rounded-xl border bg-card p-4 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md",
              origin === item.origin && "border-primary ring-2 ring-primary/20",
            )}
          >
            <span
              className={cn(
                "grid size-10 shrink-0 place-items-center rounded-lg bg-muted text-muted-foreground transition-colors",
                origin === item.origin && "bg-gradient-to-br from-primary/25 to-chart-5/20 text-primary",
              )}
            >
              <item.icon className="size-5" />
            </span>
            <span>
              <span className="block font-medium">{item.title}</span>
              <span className="block text-sm text-muted-foreground">{item.text}</span>
            </span>
          </button>
        ))}
      </div>
      <Card>
        <CardHeader>
          <CardTitle>{choice.title}</CardTitle>
          <CardDescription>{choice.text}</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={submit} className="space-y-5">
            <FieldGroup>
              {(origin === "url" || origin === "github") && (
                <Field>
                  <FieldLabel htmlFor="source-url">{origin === "github" ? "Repo" : "Adresse"}</FieldLabel>
                  <Input
                    id="source-url"
                    type="url"
                    required
                    className="font-mono"
                    placeholder={origin === "github" ? "https://github.com/eier/repo" : "https://…/program-1.2.3.tar.gz"}
                    value={text}
                    onChange={(event) => setText(event.target.value)}
                  />
                  {origin === "url" && <FieldDescription>Lenker til GitHub-repoer håndteres som GitHub.</FieldDescription>}
                </Field>
              )}
              {origin === "github" && (
                <Field>
                  <FieldLabel htmlFor="source-ref">Tag, gren eller commit</FieldLabel>
                  <Input id="source-ref" className="font-mono" placeholder="Tom = siste utgivelse" value={ref} onChange={(event) => setRef(event.target.value)} />
                </Field>
              )}
              {(origin === "aur" || origin === "arch") && (
                <Field>
                  <FieldLabel htmlFor="source-name">Pakkenavn</FieldLabel>
                  <Input
                    id="source-name"
                    required
                    className="font-mono"
                    placeholder={origin === "aur" ? "f.eks. visual-studio-code-bin" : "f.eks. foot"}
                    value={text}
                    onChange={(event) => setText(event.target.value)}
                  />
                </Field>
              )}
              {origin === "upload" && <DropZone multiple={false} files={files} onFiles={setFiles} hint="Kildekode, AppImage, .deb, .rpm, zip eller et program" />}
              {origin === "pkgbuild" && <DropZone multiple files={files} onFiles={setFiles} hint="PKGBUILD og filene den viser til, som patcher og .desktop-filer" />}
            </FieldGroup>
            {start.isPending && origin === "upload" && sent < 1 && <Progress value={sent * 100} />}
            {start.error && (
              <Alert variant="destructive">
                <AlertDescription>{start.error.message}</AlertDescription>
              </Alert>
            )}
            <Button type="submit" size="lg" disabled={!ready || start.isPending}>
              <Wand2 />
              {start.isPending ? "Starter …" : "Analyser og lag oppskrift"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}

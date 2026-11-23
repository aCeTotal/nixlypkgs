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
  { origin: "url", title: "Link", text: "Source code, AppImage, .deb, .rpm, zip or a ready-made program from a URL.", icon: Link2 },
  { origin: "github", title: "GitHub", text: "A repository, at its latest release or any tag, branch or commit.", icon: FolderGit2 },
  { origin: "upload", title: "Upload a file", text: "The same file types as a link, but from your machine. The panel shares the file with the machines.", icon: Upload },
  { origin: "aur", title: "AUR", text: "A package from the Arch User Repository. Its PKGBUILD runs like makepkg, but in Nix.", icon: Package },
  { origin: "arch", title: "Arch Linux", text: "An official Arch package, built from Arch's own PKGBUILD.", icon: ScrollText },
  { origin: "pkgbuild", title: "PKGBUILD", text: "Upload a PKGBUILD with patches and other local files.", icon: FileCode },
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
          Add derivation
        </Link>
      </Button>
      <PageHeader title="Add derivation" description="Choose where the program comes from. The wizard works out the rest, and you can adjust everything before it is published." />
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
                  <FieldLabel htmlFor="source-url">{origin === "github" ? "Repository" : "URL"}</FieldLabel>
                  <Input
                    id="source-url"
                    type="url"
                    required
                    className="font-mono"
                    placeholder={origin === "github" ? "https://github.com/owner/repo" : "https://…/program-1.2.3.tar.gz"}
                    value={text}
                    onChange={(event) => setText(event.target.value)}
                  />
                  {origin === "url" && <FieldDescription>Links to GitHub repositories are handled as GitHub.</FieldDescription>}
                </Field>
              )}
              {origin === "github" && (
                <Field>
                  <FieldLabel htmlFor="source-ref">Tag, branch or commit</FieldLabel>
                  <Input id="source-ref" className="font-mono" placeholder="Empty = latest release" value={ref} onChange={(event) => setRef(event.target.value)} />
                </Field>
              )}
              {(origin === "aur" || origin === "arch") && (
                <Field>
                  <FieldLabel htmlFor="source-name">Package name</FieldLabel>
                  <Input
                    id="source-name"
                    required
                    className="font-mono"
                    placeholder={origin === "aur" ? "e.g. visual-studio-code-bin" : "e.g. foot"}
                    value={text}
                    onChange={(event) => setText(event.target.value)}
                  />
                </Field>
              )}
              {origin === "upload" && <DropZone multiple={false} files={files} onFiles={setFiles} hint="Source code, AppImage, .deb, .rpm, zip or a program" />}
              {origin === "pkgbuild" && <DropZone multiple files={files} onFiles={setFiles} hint="The PKGBUILD and the files it references, such as patches and .desktop files" />}
            </FieldGroup>
            {start.isPending && origin === "upload" && sent < 1 && <Progress value={sent * 100} />}
            {start.error && (
              <Alert variant="destructive">
                <AlertDescription>{start.error.message}</AlertDescription>
              </Alert>
            )}
            <Button type="submit" size="lg" disabled={!ready || start.isPending}>
              <Wand2 />
              {start.isPending ? "Starting …" : "Analyse and write recipe"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}

import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/ui/dialog";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { createModule } from "./queries";

const template = `{ config, lib, pkgs, ... }:

{
}
`;

export function NewModuleDialog() {
  const navigate = useNavigate();
  const [title, setTitle] = useState("");
  const [slug, setSlug] = useState("");
  const create = useMutation({
    mutationFn: () => createModule({ slug, title, description: "", source: template }),
    onSuccess: ({ id }) => navigate({ to: "/modules/$id", params: { id: String(id) } }),
  });
  const submit = (event: FormEvent) => {
    event.preventDefault();
    create.mutate();
  };
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button>
          <Plus />
          Ny modul
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-6">
          <DialogHeader>
            <DialogTitle>Ny panelmodul</DialogTitle>
            <DialogDescription>En vanlig NixOS-modul. Velg den på typene som skal bruke den.</DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="new-module-title">Tittel</FieldLabel>
              <Input
                id="new-module-title"
                required
                value={title}
                onChange={(event) => {
                  setTitle(event.target.value);
                  setSlug(event.target.value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, ""));
                }}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor="new-module-slug">Filnavn</FieldLabel>
              <Input id="new-module-slug" required className="font-mono" pattern="[a-z0-9][a-z0-9\-]{0,62}" value={slug} onChange={(event) => setSlug(event.target.value)} />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <Button type="submit" disabled={create.isPending}>
              Opprett
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

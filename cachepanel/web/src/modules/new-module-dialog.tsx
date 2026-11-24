import { useMutation, useQuery } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/ui/dialog";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { createModule, modulesQuery } from "./queries";

const template = `{ config, lib, pkgs, ... }:

{
}
`;

export function NewModuleDialog() {
  const navigate = useNavigate();
  const head = useQuery(modulesQuery).data?.head ?? "";
  const [title, setTitle] = useState("");
  const [slug, setSlug] = useState("");
  const create = useMutation({
    mutationFn: () => createModule({ base: head, slug, title, description: "", source: template, required: false }),
    onSuccess: () => navigate({ to: "/modules/$slug", params: { slug } }),
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
          New module
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-6">
          <DialogHeader>
            <DialogTitle>New module</DialogTitle>
            <DialogDescription>A plain NixOS module, committed to nixlyos/modules. Choose it on the profiles that should use it.</DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="new-module-title">Title</FieldLabel>
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
              <FieldLabel htmlFor="new-module-slug">File name</FieldLabel>
              <Input id="new-module-slug" required className="font-mono" pattern="[a-z0-9][a-z0-9\-]{0,62}" value={slug} onChange={(event) => setSlug(event.target.value)} />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <Button type="submit" disabled={create.isPending}>
              Create
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

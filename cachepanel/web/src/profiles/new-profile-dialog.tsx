import { useMutation, useQuery } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/ui/dialog";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/ui/select";
import { treeQuery } from "@/source/queries";
import { createProfile, platformLabels, type Platform } from "./queries";

export function NewProfileDialog() {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [name, setName] = useState("");
  const [platform, setPlatform] = useState<Platform>("desktop");
  const [message, setMessage] = useState("");
  const head = useQuery({ ...treeQuery(""), enabled: open }).data?.head ?? "";
  const create = useMutation({
    mutationFn: () => createProfile({ name, title, description: "", platform, base: head, message: message.trim() }),
    onSuccess: (created) => navigate({ to: "/profiles/$name", params: { name: created.name } }),
  });
  const submit = (event: FormEvent) => {
    event.preventDefault();
    create.mutate();
  };
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>
          <Plus />
          New profile
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-6">
          <DialogHeader>
            <DialogTitle>New profile</DialogTitle>
            <DialogDescription>Starts with the required modules. A commit on main, checked in testing before stable.</DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="profile-title">Name</FieldLabel>
              <Input
                id="profile-title"
                required
                value={title}
                onChange={(event) => {
                  setTitle(event.target.value);
                  setName(event.target.value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, ""));
                }}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor="profile-name">ID (written into machine configs)</FieldLabel>
              <Input id="profile-name" required pattern="[a-z0-9][a-z0-9\-]{0,31}" value={name} onChange={(event) => setName(event.target.value)} />
            </Field>
            <Field>
              <FieldLabel>Platform</FieldLabel>
              <Select value={platform} onValueChange={(value) => setPlatform(value as Platform)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(platformLabels).map(([value, label]) => (
                    <SelectItem key={value} value={value}>
                      {label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor="profile-message">Commit message</FieldLabel>
              <Input
                id="profile-message"
                required
                placeholder={`profiles: add ${name || "<id>"}`}
                value={message}
                onChange={(event) => setMessage(event.target.value)}
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <Button type="submit" disabled={!head || !message.trim() || create.isPending}>
              Create
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

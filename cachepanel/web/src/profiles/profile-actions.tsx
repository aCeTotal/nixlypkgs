import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { Copy, FlaskConical, Trash2 } from "lucide-react";
import { useState, type FormEvent } from "react";
import { ConfirmButton } from "@/shell/confirm-button";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/ui/dialog";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { cloneProfile, deleteProfile, recheckProfile, type ProfileSummary } from "./queries";

export function ProfileActions({ profile }: { profile: ProfileSummary }) {
  const navigate = useNavigate();
  const recheck = useMutation({ mutationFn: () => recheckProfile(profile.name) });
  const remove = useMutation({ mutationFn: () => deleteProfile(profile.name), onSuccess: () => navigate({ to: "/profiles" }) });
  return (
    <>
      <Button size="sm" variant="outline" onClick={() => recheck.mutate()} disabled={profile.checkState === "running"}>
        <FlaskConical />
        Check again
      </Button>
      <CloneDialog source={profile} />
      <ConfirmButton
        label="Delete"
        icon={Trash2}
        title={`Delete the ${profile.title} profile?`}
        description="Machines on this profile keep what they run but get no more updates."
        onConfirm={() => remove.mutate()}
      />
    </>
  );
}

function CloneDialog({ source }: { source: ProfileSummary }) {
  const navigate = useNavigate();
  const [title, setTitle] = useState(`${source.title} test`);
  const [name, setName] = useState(`${source.name}-test`);
  const clone = useMutation({
    mutationFn: () => cloneProfile(source.name, { name, title }),
    onSuccess: (created) => navigate({ to: "/profiles/$name", params: { name: created.name } }),
  });
  const submit = (event: FormEvent) => {
    event.preventDefault();
    clone.mutate();
  };
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">
          <Copy />
          Clone
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-6">
          <DialogHeader>
            <DialogTitle>Clone {source.title}</DialogTitle>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="clone-title">Name</FieldLabel>
              <Input id="clone-title" required value={title} onChange={(event) => setTitle(event.target.value)} />
            </Field>
            <Field>
              <FieldLabel htmlFor="clone-name">ID</FieldLabel>
              <Input id="clone-name" required className="font-mono" value={name} onChange={(event) => setName(event.target.value)} />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <Button type="submit" disabled={clone.isPending}>
              Clone
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

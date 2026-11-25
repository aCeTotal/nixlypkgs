import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { Copy, FlaskConical, Trash2 } from "lucide-react";
import { useState, type FormEvent } from "react";
import { CommitButton } from "@/source/commit-button";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/ui/dialog";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { cloneProfile, deleteProfile, recheckProfile, type ProfileDetail } from "./queries";

export function ProfileActions({ detail }: { detail: ProfileDetail }) {
  const { profile, head } = detail;
  const navigate = useNavigate();
  const recheck = useMutation({ mutationFn: () => recheckProfile(profile.name) });
  const remove = useMutation({
    mutationFn: (message: string) => deleteProfile(profile.name, { base: head, message }),
    onSuccess: () => navigate({ to: "/profiles" }),
  });
  return (
    <>
      <Button size="sm" variant="outline" onClick={() => recheck.mutate()} disabled={profile.id === null || profile.checkState === "running"}>
        <FlaskConical />
        Check again
      </Button>
      <CloneDialog detail={detail} />
      <CommitButton
        icon={Trash2}
        variant="destructive"
        destructive
        title={`Delete the ${profile.title} profile`}
        label="Delete"
        suggestion={`profiles: delete ${profile.name}`}
        pending={remove.isPending}
        onCommit={(message) => remove.mutate(message)}
      />
    </>
  );
}

function CloneDialog({ detail: { profile, head } }: { detail: ProfileDetail }) {
  const navigate = useNavigate();
  const [title, setTitle] = useState(`${profile.title} test`);
  const [name, setName] = useState(`${profile.name}-test`);
  const [message, setMessage] = useState("");
  const clone = useMutation({
    mutationFn: () => cloneProfile(profile.name, { name, title, base: head, message: message.trim() }),
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
            <DialogTitle>Clone {profile.title}</DialogTitle>
            <DialogDescription>A commit on main. Testing builds it; stable takes it only when you approve.</DialogDescription>
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
            <Field>
              <FieldLabel htmlFor="clone-message">Commit message</FieldLabel>
              <Input
                id="clone-message"
                required
                placeholder={`profiles: clone ${profile.name} as ${name}`}
                value={message}
                onChange={(event) => setMessage(event.target.value)}
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <Button type="submit" disabled={!message.trim() || clone.isPending}>
              Clone
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

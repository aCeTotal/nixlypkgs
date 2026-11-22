import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { Copy, FlaskConical, Rocket, Trash2 } from "lucide-react";
import { useState, type FormEvent } from "react";
import { ConfirmButton } from "@/shell/confirm-button";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/ui/dialog";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { cloneProfile, deleteProfile, profileAction, type ProfileSummary } from "./queries";

export function ProfileActions({ profile }: { profile: ProfileSummary }) {
  const navigate = useNavigate();
  const act = useMutation({ mutationFn: (action: "check" | "publish") => profileAction(profile.name, action) });
  const remove = useMutation({ mutationFn: () => deleteProfile(profile.name), onSuccess: () => navigate({ to: "/profiles" }) });
  return (
    <>
      <Button size="sm" variant="outline" onClick={() => act.mutate("check")} disabled={profile.checkState === "running"}>
        <FlaskConical />
        Test på nytt
      </Button>
      {profile.checkState === "failed" && (
        <ConfirmButton
          label="Publiser likevel"
          icon={Rocket}
          title="Publisere uten bestått test?"
          description="Maskinene får kandidaten selv om testen feilet. Bruk bare når feilen gjelder en referanseprofil ingen maskiner har."
          onConfirm={() => act.mutate("publish")}
        />
      )}
      <CloneDialog source={profile} />
      <ConfirmButton
        label="Slett"
        icon={Trash2}
        title={`Slette profilen ${profile.title}?`}
        description="Maskiner som bruker profilen beholder siste publiserte oppsett, men får ingen oppdateringer."
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
          Klon
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-6">
          <DialogHeader>
            <DialogTitle>Klon {source.title}</DialogTitle>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="clone-title">Navn</FieldLabel>
              <Input id="clone-title" required value={title} onChange={(event) => setTitle(event.target.value)} />
            </Field>
            <Field>
              <FieldLabel htmlFor="clone-name">ID</FieldLabel>
              <Input id="clone-name" required className="font-mono" value={name} onChange={(event) => setName(event.target.value)} />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <Button type="submit" disabled={clone.isPending}>
              Klon
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

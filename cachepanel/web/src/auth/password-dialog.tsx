import { useMutation } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { toast } from "sonner";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/ui/dialog";
import { Field, FieldError, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { changePassword } from "./session";

const minLength = 8;

type PasswordDialogProps = { open: boolean; onOpenChange: (open: boolean) => void };

export function PasswordDialog({ open, onOpenChange }: PasswordDialogProps) {
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [repeat, setRepeat] = useState("");
  const mismatch = repeat !== "" && next !== repeat;
  const change = useMutation({
    mutationFn: () => changePassword(current, next),
    onSuccess: () => {
      toast.success("Passordet er byttet – andre økter er logget ut");
      onOpenChange(false);
      setCurrent("");
      setNext("");
      setRepeat("");
    },
  });
  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (!mismatch) change.mutate();
  };
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={submit} className="space-y-6">
          <DialogHeader>
            <DialogTitle>Bytt passord</DialogTitle>
            <DialogDescription>Minst {minLength} tegn. Alle andre innlogginger avsluttes.</DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="current-password">Nåværende passord</FieldLabel>
              <Input id="current-password" type="password" autoComplete="current-password" required value={current} onChange={(event) => setCurrent(event.target.value)} />
            </Field>
            <Field>
              <FieldLabel htmlFor="new-password">Nytt passord</FieldLabel>
              <Input id="new-password" type="password" autoComplete="new-password" minLength={minLength} required value={next} onChange={(event) => setNext(event.target.value)} />
            </Field>
            <Field data-invalid={mismatch}>
              <FieldLabel htmlFor="repeat-password">Gjenta nytt passord</FieldLabel>
              <Input id="repeat-password" type="password" autoComplete="new-password" required aria-invalid={mismatch} value={repeat} onChange={(event) => setRepeat(event.target.value)} />
              {mismatch && <FieldError>Passordene er ikke like</FieldError>}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <Button type="submit" disabled={change.isPending || mismatch}>
              Bytt passord
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

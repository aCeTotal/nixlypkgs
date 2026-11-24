import { GitCommitVertical } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/ui/dialog";
import { Field, FieldLabel } from "@/ui/field";
import { Textarea } from "@/ui/textarea";

type CommitDialogProps = {
  open: boolean;
  suggestion: string;
  pending: boolean;
  onOpenChange: (open: boolean) => void;
  onCommit: (message: string) => void;
};

export function CommitDialog({ open, suggestion, pending, onOpenChange, onCommit }: CommitDialogProps) {
  const [message, setMessage] = useState(suggestion);
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onCommit(message.trim());
  };
  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (next) setMessage(suggestion);
        onOpenChange(next);
      }}
    >
      <DialogContent>
        <form onSubmit={submit} className="space-y-6">
          <DialogHeader>
            <DialogTitle>Commit to main</DialogTitle>
            <DialogDescription>The panel builds it in testing; stable takes it only when you approve.</DialogDescription>
          </DialogHeader>
          <Field>
            <FieldLabel htmlFor="commit-message">Message</FieldLabel>
            <Textarea id="commit-message" value={message} onChange={(event) => setMessage(event.target.value)} />
          </Field>
          <DialogFooter>
            <Button type="submit" disabled={!message.trim() || pending}>
              <GitCommitVertical />
              Commit
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

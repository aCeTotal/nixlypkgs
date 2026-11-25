import { GitCommitVertical, Wand2 } from "lucide-react";
import { useState, type FormEvent } from "react";
import { CodeEditor } from "@/editor/code-editor";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/ui/dialog";
import { Field, FieldLabel } from "@/ui/field";
import { Textarea } from "@/ui/textarea";

export type CommitDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  label: string;
  suggestion: string;
  pending: boolean;
  destructive?: boolean;
  // Diffed above the message.
  changes?: { path: string; original: string; current: string };
  onCommit: (message: string) => void;
};

// Every change needs a message.
export function CommitDialog({ open, onOpenChange, title, label, suggestion, pending, destructive, changes, onCommit }: CommitDialogProps) {
  const [message, setMessage] = useState("");
  const [shown, setShown] = useState(open);
  // Fresh message on each open.
  if (open !== shown) {
    setShown(open);
    setMessage("");
  }
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onCommit(message.trim());
  };
  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
    >
      <DialogContent className={changes ? "sm:max-w-4xl" : undefined}>
        <form onSubmit={submit} className="space-y-5">
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>A commit on main. Testing builds it; stable takes it only when you approve.</DialogDescription>
          </DialogHeader>
          {changes && (
            <div className="h-[45vh]">
              <CodeEditor path={changes.path} value={changes.current} original={changes.original} readOnly />
            </div>
          )}
          <Field>
            <div className="flex items-center justify-between gap-2">
              <FieldLabel htmlFor="commit-message">Commit message</FieldLabel>
              <Button type="button" variant="link" size="sm" className="h-auto px-0" onClick={() => setMessage(suggestion)}>
                <Wand2 />
                Use suggestion
              </Button>
            </div>
            <Textarea
              id="commit-message"
              placeholder={suggestion}
              value={message}
              onChange={(event) => setMessage(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter" && (event.metaKey || event.ctrlKey) && message.trim()) onCommit(message.trim());
              }}
            />
          </Field>
          <DialogFooter>
            <Button type="submit" variant={destructive ? "destructive" : "default"} disabled={!message.trim() || pending}>
              <GitCommitVertical />
              {label}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

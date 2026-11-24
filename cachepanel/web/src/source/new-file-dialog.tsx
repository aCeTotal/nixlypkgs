import { FilePlus } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/ui/dialog";
import { Field, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";

type NewFileDialogProps = { folder: string; onCreate: (path: string) => void };

export function NewFileDialog({ folder, onCreate }: NewFileDialogProps) {
  const [open, setOpen] = useState(false);
  const [path, setPath] = useState("");
  const submit = (event: FormEvent) => {
    event.preventDefault();
    setOpen(false);
    onCreate(path.trim().replace(/^\/+/, ""));
  };
  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (next) setPath(folder ? `${folder}/` : "");
        setOpen(next);
      }}
    >
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">
          <FilePlus />
          New file
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-6">
          <DialogHeader>
            <DialogTitle>New file</DialogTitle>
            <DialogDescription>It opens empty in the editor; commit it when it is ready.</DialogDescription>
          </DialogHeader>
          <Field>
            <FieldLabel htmlFor="new-file-path">Path</FieldLabel>
            <Input id="new-file-path" className="font-mono" placeholder="pkgs/hello/default.nix" value={path} onChange={(event) => setPath(event.target.value)} />
          </Field>
          <DialogFooter>
            <Button type="submit" disabled={!path.trim() || path.trim().endsWith("/")}>
              Open
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

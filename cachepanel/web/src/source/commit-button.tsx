import { useState, type ComponentType } from "react";
import { Button } from "@/ui/button";
import { CommitDialog, type CommitDialogProps } from "./commit-dialog";

type CommitButtonProps = Omit<CommitDialogProps, "open" | "onOpenChange"> & {
  icon: ComponentType;
  disabled?: boolean;
  variant?: "default" | "outline" | "ghost" | "destructive";
};

// Asks for a message, then commits.
export function CommitButton({ icon: Icon, disabled, variant = "default", onCommit, ...dialog }: CommitButtonProps) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button size="sm" variant={variant} onClick={() => setOpen(true)} disabled={disabled || dialog.pending}>
        <Icon />
        {dialog.label}
      </Button>
      <CommitDialog
        {...dialog}
        open={open}
        onOpenChange={setOpen}
        onCommit={(message) => {
          setOpen(false);
          onCommit(message);
        }}
      />
    </>
  );
}

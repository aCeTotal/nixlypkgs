import { useMutation } from "@tanstack/react-query";
import { KeyRound, Plus, Trash2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { timeAgo } from "@/format/time";
import { ConfirmButton } from "@/shell/confirm-button";
import { Button } from "@/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Textarea } from "@/ui/textarea";
import { addKey, removeKey, type PushKey } from "./queries";

export function KeysCard({ keys }: { keys: PushKey[] }) {
  const remove = useMutation({ mutationFn: removeKey, onSuccess: () => toast.success("Key removed") });
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <KeyRound className="size-4 text-primary" />
          Push keys
        </CardTitle>
        <CardDescription>SSH keys that may push to nixlypkgs. Each push is built in testing before stable can take it.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        {keys.length === 0 && <p className="text-sm text-muted-foreground">No key may push yet.</p>}
        {keys.length > 0 && (
          <ul className="divide-y">
            {keys.map((key) => (
              <li key={key.id} className="flex flex-wrap items-center gap-3 py-2.5 first:pt-0">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{key.name}</p>
                  <p className="truncate font-mono text-xs text-muted-foreground">
                    {key.type} {key.fingerprint}
                  </p>
                </div>
                <span className="shrink-0 text-xs text-muted-foreground">{timeAgo(key.createdAt)}</span>
                <ConfirmButton
                  label="Remove"
                  icon={Trash2}
                  title={`Remove ${key.name}?`}
                  description="The key can no longer push. Commits it pushed stay."
                  onConfirm={() => remove.mutate(key.id)}
                  disabled={remove.isPending}
                />
              </li>
            ))}
          </ul>
        )}
        <AddKeyForm />
      </CardContent>
    </Card>
  );
}

function AddKeyForm() {
  const [name, setName] = useState("");
  const [publicKey, setPublicKey] = useState("");
  const add = useMutation({
    mutationFn: addKey,
    onSuccess: (key) => {
      toast.success(`${key.name} may push`);
      setName("");
      setPublicKey("");
    },
  });
  const paste = (value: string) => {
    setPublicKey(value);
    const comment = value.trim().split(/\s+/)[2];
    if (!name && comment) setName(comment);
  };
  return (
    <form
      className="rounded-lg border border-dashed p-4"
      onSubmit={(event) => {
        event.preventDefault();
        add.mutate({ name, publicKey });
      }}
    >
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="key">Public key</FieldLabel>
          <Textarea
            id="key"
            className="font-mono text-xs"
            placeholder="ssh-ed25519 AAAA… you@laptop"
            value={publicKey}
            onChange={(event) => paste(event.target.value)}
          />
        </Field>
        <Field>
          <FieldLabel htmlFor="key-name">Name</FieldLabel>
          <Input id="key-name" value={name} onChange={(event) => setName(event.target.value)} />
        </Field>
        <Button type="submit" className="justify-self-start" disabled={!name.trim() || !publicKey.trim() || add.isPending}>
          <Plus />
          Allow key
        </Button>
      </FieldGroup>
    </form>
  );
}

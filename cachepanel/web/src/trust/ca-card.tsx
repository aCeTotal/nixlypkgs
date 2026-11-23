import { useMutation } from "@tanstack/react-query";
import { Download, KeyRound, RefreshCw, ShieldPlus } from "lucide-react";
import { toast } from "sonner";
import { dateTime, daysUntil, timeAgo } from "@/format/time";
import { ConfirmButton } from "@/shell/confirm-button";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { createCA, fingerprintPairs, type CA } from "./queries";

const expiryWarningDays = 365;

export function CreateCACard() {
  const create = useMutation({ mutationFn: createCA, onSuccess: () => toast.success("NixlyOS CA created") });
  return (
    <Card className="relative overflow-hidden border-primary/40">
      <div className="pointer-events-none absolute -top-24 -right-24 size-64 rounded-full bg-primary/15 blur-3xl" />
      <CardContent className="relative flex flex-col items-center gap-4 py-10 text-center">
        <span className="grid size-14 place-items-center rounded-2xl bg-gradient-to-br from-primary/25 to-primary/5 text-primary">
          <ShieldPlus className="size-7" />
        </span>
        <div className="max-w-md space-y-1">
          <p className="text-lg font-semibold">No NixlyOS CA yet</p>
          <p className="text-sm text-muted-foreground">
            Releases stop at signing until a CA exists. The private key stays on this server, readable by the panel alone.
          </p>
        </div>
        <Button onClick={() => create.mutate()} disabled={create.isPending}>
          <KeyRound />
          Create NixlyOS CA
        </Button>
      </CardContent>
    </Card>
  );
}

export function ActiveCACard({ ca, history }: { ca: CA; history: CA[] }) {
  const rotate = useMutation({ mutationFn: createCA, onSuccess: () => toast.success("New CA active; update the kernel's CA input next") });
  const daysLeft = daysUntil(ca.notAfter);
  const retired = history.filter((entry) => entry.retiredAt !== null);
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <KeyRound className="size-4 text-primary" />
          {ca.subject}
        </CardTitle>
        <CardDescription>Signs every kernel, module and boot loader the panel releases.</CardDescription>
        <CardAction className="flex gap-2">
          <Button asChild size="sm" variant="outline">
            <a href={`/api/trust/ca/${ca.id}.pem`} download="nixlyos-ca.pem">
              <Download />
              PEM
            </a>
          </Button>
          <Button asChild size="sm" variant="outline">
            <a href={`/api/trust/ca/${ca.id}.der`} download="nixlyos-ca.der">
              <Download />
              DER
            </a>
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent className="space-y-4">
        <dl className="grid gap-3 text-sm sm:grid-cols-3">
          <div>
            <dt className="text-muted-foreground">Created</dt>
            <dd className="font-medium">{dateTime(ca.createdAt)}</dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Valid until</dt>
            <dd className={daysLeft < expiryWarningDays ? "font-medium text-destructive" : "font-medium"}>
              {dateTime(ca.notAfter)} <span className="text-muted-foreground">({timeAgo(ca.notAfter)})</span>
            </dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Key</dt>
            <dd className="font-medium">RSA-2048, SHA-512 signatures</dd>
          </div>
        </dl>
        <div>
          <p className="mb-1 text-sm text-muted-foreground">SHA-256 fingerprint</p>
          <p className="rounded-lg bg-muted/60 px-3 py-2 font-mono text-xs break-all">{fingerprintPairs(ca.fingerprint)}</p>
        </div>
        {retired.length > 0 && (
          <div className="text-sm">
            <p className="mb-1 text-muted-foreground">Retired</p>
            <ul className="space-y-1">
              {retired.map((entry) => (
                <li key={entry.id} className="flex items-baseline gap-2">
                  <span className="font-mono text-xs text-muted-foreground">{entry.fingerprint.slice(0, 16)}</span>
                  <span className="min-w-0 flex-1 truncate">{entry.subject}</span>
                  <span className="shrink-0 text-xs text-muted-foreground">retired {timeAgo(entry.retiredAt)}</span>
                </li>
              ))}
            </ul>
          </div>
        )}
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-dashed p-3">
          <p className="max-w-xl text-xs text-muted-foreground">
            Rotation retires this CA. Signing pauses until the kernel embeds the new one: run{" "}
            <code className="font-mono">nix flake update nixlyos-ca</code> in kernel_nixlyos and bump nixlypkgs. Machines then run{" "}
            <code className="font-mono">nixlyos-secureboot update</code>; the previous CA stays in db so older generations keep booting.
          </p>
          <ConfirmButton
            label="Rotate CA"
            icon={RefreshCw}
            title="Rotate the NixlyOS CA?"
            description="A new key pair replaces this one. Nothing gets signed again until the kernel embeds the new CA, and every machine must update its firmware keys before booting a release signed by it."
            onConfirm={() => rotate.mutate()}
            disabled={rotate.isPending}
          />
        </div>
      </CardContent>
    </Card>
  );
}

import { FileSignature } from "lucide-react";
import { PlatformIcon } from "@/profiles/platform-icon";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import type { Release, SignatureState } from "./queries";

const states: Record<SignatureState, { label: string; tone: string }> = {
  signed: { label: "Signed", tone: "bg-success-soft text-success" },
  old: { label: "Old CA", tone: "bg-warning-soft text-warning-foreground" },
  unsigned: { label: "Unsigned", tone: "bg-danger-soft text-destructive" },
  none: { label: "No release", tone: "bg-muted text-muted-foreground" },
};

export function ReleasesCard({ releases }: { releases: Release[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <FileSignature className="size-4 text-primary" />
          Releases
        </CardTitle>
        <CardDescription>A release is signed when it passes its checks; approval moves the signed tree to stable.</CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="divide-y">
          {releases.map((release) => (
            <li key={release.profile} className="flex flex-wrap items-center gap-3 py-2.5 first:pt-0 last:pb-0">
              <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
                <PlatformIcon platform={release.platform} className="size-4" />
              </span>
              <span className="min-w-0 flex-1 truncate font-medium">{release.title}</span>
              <Signature branch="Stable" state={release.stable} />
              <Signature branch="Testing" state={release.testing} />
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}

function Signature({ branch, state }: { branch: string; state: SignatureState }) {
  const style = states[state];
  return (
    <span className={cn("inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium", style.tone)}>
      <span className="opacity-70">{branch}</span>
      {style.label}
    </span>
  );
}

import { ArrowRight } from "lucide-react";
import { shortSha } from "@/format/sha";
import { dateTime, timeAgo } from "@/format/time";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { CheckBadge } from "./check-badge";
import type { ProfileSummary } from "./queries";

const steps = ["Lagret endring", "Kandidat bygget", "Evaluert og bygget på alle referanseprofiler", "Publisert", "Maskinene henter ved neste oppdatering"];

function Release({ label, tree, rev, note }: { label: string; tree: string | null; rev: string | null; note: string }) {
  return (
    <div className="rounded-lg border p-4">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className="mt-1 font-mono text-sm">nixlypkgs {shortSha(rev)}</p>
      <p className="font-mono text-xs text-muted-foreground">tre {shortSha(tree)}</p>
      <p className="mt-2 text-xs text-muted-foreground">{note}</p>
    </div>
  );
}

export function ProfileStatus({ profile }: { profile: ProfileSummary }) {
  const inSync = profile.candidateTree === profile.publishedTree && profile.candidateRev === profile.publishedRev;
  return (
    <div className="grid gap-4 xl:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Utrulling</CardTitle>
          <CardDescription>Ingenting når maskinene før det er testet.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <ol className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            {steps.map((step, index) => (
              <li key={step} className="flex items-center gap-2">
                {index > 0 && <ArrowRight className="size-3" />}
                <span className="rounded-full bg-muted px-2 py-0.5">{step}</span>
              </li>
            ))}
          </ol>
          <div className="grid gap-3 sm:grid-cols-2">
            <Release label="Kandidat" tree={profile.candidateTree} rev={profile.candidateRev} note={inSync ? "Samme som publisert" : "Venter på test"} />
            <Release
              label="Publisert"
              tree={profile.publishedTree}
              rev={profile.publishedRev}
              note={profile.publishedAt ? `${dateTime(profile.publishedAt)} (${timeAgo(profile.publishedAt)})` : "Aldri publisert"}
            />
          </div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            Siste test <CheckBadge state={profile.checkState} />
          </CardTitle>
          <CardDescription>{profile.checkedAt ? `Kjørt ${timeAgo(profile.checkedAt)}` : "Ikke kjørt ennå"}</CardDescription>
        </CardHeader>
        <CardContent>
          {profile.checkError ? (
            <pre className="max-h-[28rem] overflow-auto rounded-lg bg-danger-soft p-3 font-mono text-xs whitespace-pre-wrap text-destructive">
              {profile.checkError}
            </pre>
          ) : (
            <p className="text-sm text-muted-foreground">Ingen feil.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

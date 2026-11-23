import { ArrowRight } from "lucide-react";
import type { ReactNode } from "react";
import { shortSha } from "@/format/sha";
import { dateTime, timeAgo } from "@/format/time";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { BranchBadge } from "./branch-badge";
import { CheckBadge } from "./check-badge";
import type { ProfileSummary } from "./queries";

const steps = ["Saved change", "Built and checked on all reference machines", "Testing", "Approved", "Stable"];

function released(at: string | null, never: string) {
  return at ? `${dateTime(at)} (${timeAgo(at)})` : never;
}

type ReleaseProps = { label: ReactNode; tree: string | null; rev: string | null; note: string };

function Release({ label, tree, rev, note }: ReleaseProps) {
  return (
    <div className="rounded-lg border p-4">
      <div className="text-sm text-muted-foreground">{label}</div>
      <p className="mt-1 font-mono text-sm">nixlypkgs {shortSha(rev)}</p>
      <p className="font-mono text-xs text-muted-foreground">tree {shortSha(tree)}</p>
      <p className="mt-2 text-xs text-muted-foreground">{note}</p>
    </div>
  );
}

export function ProfileStatus({ profile }: { profile: ProfileSummary }) {
  const inSync = profile.candidateTree === profile.testingTree && profile.candidateRev === profile.testingRev;
  return (
    <div className="grid gap-4 xl:grid-cols-[3fr_2fr]">
      <Card>
        <CardHeader>
          <CardTitle>Rollout</CardTitle>
          <CardDescription>Everything new goes to testing. Stable only changes when you approve.</CardDescription>
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
          <div className="grid gap-3 sm:grid-cols-3">
            <Release label="Candidate" tree={profile.candidateTree} rev={profile.candidateRev} note={inSync ? "Same as testing" : "Awaiting check"} />
            <Release
              label={<BranchBadge branch="testing" />}
              tree={profile.testingTree}
              rev={profile.testingRev}
              note={released(profile.testingAt, "Nothing checked yet")}
            />
            <Release
              label={<BranchBadge branch="stable" />}
              tree={profile.stableTree}
              rev={profile.stableRev}
              note={released(profile.stableAt, "Not approved yet")}
            />
          </div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            Latest check <CheckBadge state={profile.checkState} />
          </CardTitle>
          <CardDescription>{profile.checkedAt ? `Ran ${timeAgo(profile.checkedAt)}` : "Not run yet"}</CardDescription>
        </CardHeader>
        <CardContent>
          {profile.checkError ? (
            <pre className="max-h-[28rem] overflow-auto rounded-lg bg-danger-soft p-3 font-mono text-xs whitespace-pre-wrap text-destructive">
              {profile.checkError}
            </pre>
          ) : (
            <p className="text-sm text-muted-foreground">No errors.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

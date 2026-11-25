import { ArrowRight, CircleCheck, DatabaseZap, FileMinus, FilePen, FilePlus, GitCommitVertical, type LucideIcon } from "lucide-react";
import { useState } from "react";
import { formatBytes } from "@/format/bytes";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { Button } from "@/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import { ApproveButton } from "./approve-button";
import { BranchBadge } from "./branch-badge";
import { PlatformIcon } from "./platform-icon";
import type { Approval, AwaitingProfile, FileChange } from "./queries";

const commitPreview = 6;

const fileStyles: Record<FileChange, { icon: LucideIcon; tone: string; label: string }> = {
  added: { icon: FilePlus, tone: "bg-success-soft text-success", label: "new" },
  changed: { icon: FilePen, tone: "bg-warning-soft text-warning-foreground", label: "changed" },
  removed: { icon: FileMinus, tone: "bg-danger-soft text-destructive", label: "removed" },
};

export function BaseCard({ approval }: { approval: Approval }) {
  if (approval.profiles.length === 0) {
    return (
      <Card className="bg-muted/30">
        <CardContent className="flex items-center gap-3 text-sm">
          <CircleCheck className="size-5 shrink-0 text-success" />
          <p>
            <span className="font-medium">Stable has testing's base.</span>{" "}
            <span className="text-muted-foreground">New revisions, module edits and profile settings wait here.</span>
          </p>
        </CardContent>
      </Card>
    );
  }
  return (
    <Card className="relative overflow-hidden border-warning/40">
      <div className="pointer-events-none absolute -top-24 -right-24 size-56 rounded-full bg-warning/15 blur-3xl" />
      <CardHeader className="relative">
        <CardTitle className="flex items-center gap-2">
          Base
          <BranchBadge branch="testing" />
          <ArrowRight className="size-4 text-muted-foreground" />
          <BranchBadge branch="stable" />
        </CardTitle>
        <CardDescription>
          Revision, modules and profile settings, for every profile at once. Approved derivations keep their stable version.
        </CardDescription>
      </CardHeader>
      <CardContent className="relative grid gap-5 lg:grid-cols-2">
        <ul className="space-y-3">
          {approval.profiles.map((profile) => (
            <AwaitingRow key={profile.id} profile={profile} />
          ))}
        </ul>
        <CommitList commits={approval.commits} first={approval.profiles.some((profile) => profile.baseRev === null)} />
      </CardContent>
      <CardFooter className="relative justify-end">
        <ApproveButton
          request={{ profiles: approval.profiles, derivations: [] }}
          label="Approve base"
          title="Move the base to stable?"
          description={`All ${approval.profiles.length} profiles get testing's revision, modules and settings. Stable is rebuilt and signed before machines get it.`}
        />
      </CardFooter>
    </Card>
  );
}

function AwaitingRow({ profile }: { profile: AwaitingProfile }) {
  return (
    <li className="rounded-lg border bg-card/60 p-3">
      <div className="flex items-center gap-3">
        <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
          <PlatformIcon platform={profile.platform} className="size-4" />
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate font-medium">{profile.title}</p>
          <p className="truncate font-mono text-xs text-muted-foreground">
            {profile.baseRev ? shortSha(profile.baseRev) : "first release"} → {shortSha(profile.testingRev)}
          </p>
        </div>
        <span className="shrink-0 text-xs text-muted-foreground">{timeAgo(profile.testingAt)}</span>
      </div>
      {profile.paths !== null && (
        <p className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground">
          <DatabaseZap className="size-3.5 text-primary" />
          All {profile.paths.toLocaleString()} paths cached, {formatBytes(profile.bytes)}
        </p>
      )}
      {profile.baseRev === null && <p className="mt-2 text-xs text-muted-foreground">The whole setup, {profile.files.length} files.</p>}
      {profile.baseRev !== null && profile.files.length > 0 && (
        <div className="mt-2.5 flex flex-wrap gap-1.5">
          {profile.files.map((file) => {
            const style = fileStyles[file.change];
            return (
              <span
                key={file.path}
                title={`${file.path} (${style.label})`}
                className={cn("inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 font-mono text-[0.7rem]", style.tone)}
              >
                <style.icon className="size-3" />
                {file.path}
              </span>
            );
          })}
        </div>
      )}
    </li>
  );
}

function CommitList({ commits, first }: { commits: Approval["commits"]; first: boolean }) {
  const [expanded, setExpanded] = useState(false);
  if (first && commits.length === 0) {
    return <p className="text-sm text-muted-foreground">First approval: everything becomes stable for the first time.</p>;
  }
  if (commits.length === 0) {
    return <p className="text-sm text-muted-foreground">No new commits, only module or profile changes.</p>;
  }
  const shown = expanded ? commits : commits.slice(0, commitPreview);
  return (
    <div className="space-y-2">
      <p className="text-sm font-medium">New commits ({commits.length})</p>
      <ul className="space-y-1.5">
        {shown.map((commit) => (
          <li key={commit.sha} className="flex items-baseline gap-2 text-sm">
            <GitCommitVertical className="size-3.5 shrink-0 translate-y-0.5 text-muted-foreground" />
            <span className="shrink-0 font-mono text-xs text-muted-foreground">{shortSha(commit.sha)}</span>
            <span className="min-w-0 flex-1 truncate">{commit.subject}</span>
            <span className="shrink-0 text-xs text-muted-foreground">{timeAgo(commit.committedAt)}</span>
          </li>
        ))}
      </ul>
      {commits.length > commitPreview && (
        <Button variant="link" size="sm" className="h-auto px-0" onClick={() => setExpanded(!expanded)}>
          {expanded ? "Show fewer" : `Show all ${commits.length}`}
        </Button>
      )}
    </div>
  );
}

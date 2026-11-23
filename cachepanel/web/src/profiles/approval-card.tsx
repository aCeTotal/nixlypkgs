import { useMutation, useSuspenseQuery } from "@tanstack/react-query";
import { ArrowRight, CircleCheck, FileMinus, FilePen, FilePlus, GitCommitVertical, type LucideIcon } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/ui/alert-dialog";
import { Button } from "@/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import { BranchBadge } from "./branch-badge";
import { PlatformIcon } from "./platform-icon";
import { approvalQuery, approve, type Approval, type AwaitingProfile, type FileChange } from "./queries";

const commitPreview = 6;

const fileStyles: Record<FileChange, { icon: LucideIcon; tone: string; label: string }> = {
  added: { icon: FilePlus, tone: "bg-success-soft text-success", label: "new" },
  changed: { icon: FilePen, tone: "bg-warning-soft text-warning-foreground", label: "changed" },
  removed: { icon: FileMinus, tone: "bg-danger-soft text-destructive", label: "removed" },
};

export function ApprovalCard() {
  const { data } = useSuspenseQuery(approvalQuery);
  if (data.profiles.length === 0) {
    return (
      <Card className="bg-muted/30">
        <CardContent className="flex items-center gap-3 text-sm">
          <CircleCheck className="size-5 shrink-0 text-success" />
          <p>
            <span className="font-medium">Stable and testing match.</span>{" "}
            <span className="text-muted-foreground">New changes land in testing and wait here for approval.</span>
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
          <BranchBadge branch="testing" />
          <ArrowRight className="size-4 text-muted-foreground" />
          <BranchBadge branch="stable" />
        </CardTitle>
        <CardDescription>
          {data.profiles.length} {data.profiles.length === 1 ? "profile has" : "profiles have"} news in testing. Machines on stable
          get it only once you approve.
        </CardDescription>
      </CardHeader>
      <CardContent className="relative grid gap-5 lg:grid-cols-2">
        <ul className="space-y-3">
          {data.profiles.map((profile) => (
            <AwaitingRow key={profile.id} profile={profile} />
          ))}
        </ul>
        <CommitList commits={data.commits} first={data.profiles.some((profile) => profile.stableRev === null)} />
      </CardContent>
      <CardFooter className="relative justify-end">
        <ApproveButton approval={data} />
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
            {profile.stableRev ? shortSha(profile.stableRev) : "first release"} → {shortSha(profile.testingRev)}
          </p>
        </div>
        <span className="shrink-0 text-xs text-muted-foreground">{timeAgo(profile.testingAt)}</span>
      </div>
      {profile.stableRev === null && <p className="mt-2 text-xs text-muted-foreground">The whole setup, {profile.files.length} files.</p>}
      {profile.stableRev !== null && profile.files.length > 0 && (
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

function ApproveButton({ approval }: { approval: Approval }) {
  const ship = useMutation({ mutationFn: () => approve(approval), onSuccess: () => toast.success("Testing is now stable") });
  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button disabled={ship.isPending}>
          <CircleCheck />
          Approve testing
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Move testing to stable?</AlertDialogTitle>
          <AlertDialogDescription>
            All {approval.profiles.length} profiles above become stable. Stable machines get them on their next update.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction onClick={() => ship.mutate()}>Approve</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

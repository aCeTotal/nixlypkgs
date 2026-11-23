import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { Layers } from "lucide-react";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { BranchBadge } from "@/profiles/branch-badge";
import { CheckBadge } from "@/profiles/check-badge";
import { PlatformIcon } from "@/profiles/platform-icon";
import { profilesQuery, testingAhead } from "@/profiles/queries";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";

export function ProfilesCard() {
  const { data: profiles = [] } = useQuery(profilesQuery);
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Layers className="size-4 text-primary" />
          Profiles in service
        </CardTitle>
        <CardDescription>What stable machines on each profile get on their next update.</CardDescription>
      </CardHeader>
      <CardContent className="divide-y">
        {profiles.map((profile) => (
          <Link
            key={profile.id}
            to="/profiles/$name"
            params={{ name: profile.name }}
            className="-mx-2 flex items-center gap-3 rounded-lg px-2 py-2.5 transition-colors hover:bg-muted/60"
          >
            <span className="grid size-9 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
              <PlatformIcon platform={profile.platform} className="size-4.5" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="truncate font-medium">{profile.title}</p>
              <p className="truncate font-mono text-xs text-muted-foreground">
                {profile.stableRev ? `${shortSha(profile.stableRev)} · ${timeAgo(profile.stableAt)}` : "no stable yet"}
              </p>
            </div>
            {testingAhead(profile) && <BranchBadge branch="testing">Awaiting</BranchBadge>}
            <CheckBadge state={profile.checkState} />
          </Link>
        ))}
      </CardContent>
    </Card>
  );
}

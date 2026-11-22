import { useSuspenseQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { Blocks, GitCommitVertical, Package } from "lucide-react";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { PageHeader } from "@/shell/page-header";
import { Badge } from "@/ui/badge";
import { CheckBadge } from "./check-badge";
import { NewProfileDialog } from "./new-profile-dialog";
import { PlatformIcon } from "./platform-icon";
import { platformLabels, profilesQuery } from "./queries";

export function ProfilesPage() {
  const { data: profiles } = useSuspenseQuery(profilesQuery);
  return (
    <div className="space-y-4">
      <PageHeader
        title="Profiler"
        description="Et oppsett som Desktop, Laptop eller HTPC: valgte moduler, pakker og nixlypkgs-revisjon. Maskinvaremoduler velges automatisk på hver maskin."
        actions={<NewProfileDialog />}
      />
      <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
        {profiles.map((profile) => (
          <Link
            key={profile.id}
            to="/profiles/$name"
            params={{ name: profile.name }}
            className="group relative overflow-hidden rounded-xl border bg-card p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md"
          >
            <div className="pointer-events-none absolute -top-16 -right-16 size-40 rounded-full bg-primary/10 blur-2xl transition group-hover:bg-primary/20" />
            <div className="relative space-y-4">
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <span className="grid size-11 place-items-center rounded-xl bg-gradient-to-br from-primary/25 to-chart-5/20 text-primary">
                    <PlatformIcon platform={profile.platform} className="size-5" />
                  </span>
                  <div>
                    <h3 className="text-lg font-semibold tracking-tight">{profile.title}</h3>
                    <p className="font-mono text-xs text-muted-foreground">{profile.name}</p>
                  </div>
                </div>
                <Badge variant="outline">{platformLabels[profile.platform]}</Badge>
              </div>
              {profile.description && <p className="text-sm text-muted-foreground">{profile.description}</p>}
              <div className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted-foreground">
                <span className="flex items-center gap-1.5">
                  <Blocks className="size-3.5" />
                  {profile.catalogCount + profile.moduleCount} moduler
                </span>
                <span className="flex items-center gap-1.5">
                  <Package className="size-3.5" />
                  {profile.packageCount} pakker
                </span>
                <span className="flex items-center gap-1.5">
                  <GitCommitVertical className="size-3.5" />
                  {profile.publishedRev ? `${shortSha(profile.publishedRev)} · ${timeAgo(profile.publishedAt)}` : "ikke publisert"}
                </span>
              </div>
              <div className="border-t pt-3">
                <CheckBadge state={profile.checkState} />
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}

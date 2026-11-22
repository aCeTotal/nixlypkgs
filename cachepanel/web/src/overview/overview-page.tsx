import { useQuery, useSuspenseQuery } from "@tanstack/react-query";
import { Database, HardDrive, Hammer, Layers } from "lucide-react";
import { formatBytes } from "@/format/bytes";
import { profilesQuery } from "@/profiles/queries";
import { PageHeader } from "@/shell/page-header";
import { StatTile } from "@/shell/stat-tile";
import { QueueCard, RecentCard, RunningBuilds } from "./build-activity";
import { overviewQuery } from "./queries";
import { ProfilesCard } from "./profiles-card";
import { WatcherCard } from "./watcher-card";

export function OverviewPage() {
  const { data } = useSuspenseQuery(overviewQuery);
  const states = data.cache.states;
  const usedDisk = data.disk.total - data.disk.free;
  const { data: profiles = [] } = useQuery(profilesQuery);
  const passed = profiles.filter((profile) => profile.checkState === "passed" || profile.checkState === "skipped").length;
  return (
    <div className="space-y-6">
      <PageHeader title="Oversikt" description="Cache, profiler og bygg i sanntid." />
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatTile
          label="Profiler klare"
          value={`${passed}/${profiles.length}`}
          hint="testet og publisert"
          icon={Layers}
          tone={passed === profiles.length ? "success" : "warning"}
        />
        <StatTile
          label="Bygg"
          value={`${states.building ?? 0} / ${states.queued ?? 0}`}
          hint="kjører / i kø"
          icon={Hammer}
          tone="info"
        />
        <StatTile
          label="Cachede versjoner"
          value={states.cached ?? 0}
          hint={`${data.cache.packages} pakker · ${formatBytes(data.cache.closureBytes)}`}
          icon={Database}
        />
        <StatTile
          label="Ledig i /nix/store"
          value={formatBytes(data.disk.free)}
          hint={`${Math.round((usedDisk / data.disk.total) * 100)} % av ${formatBytes(data.disk.total)} brukt`}
          icon={HardDrive}
          tone={data.disk.free < data.disk.total * 0.1 ? "danger" : "primary"}
        />
      </div>
      <div className="grid gap-4 xl:grid-cols-2">
        <WatcherCard watcher={data.watcher} />
        <ProfilesCard />
      </div>
      <div className="grid gap-4 xl:grid-cols-3">
        <RunningBuilds />
        <QueueCard queue={data.cache.queue} />
        <RecentCard recent={data.cache.recent} />
      </div>
    </div>
  );
}

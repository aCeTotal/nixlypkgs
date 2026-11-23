import { useSuspenseQuery } from "@tanstack/react-query";
import { CalendarClock, FileSignature, ShieldCheck } from "lucide-react";
import { timeAgo } from "@/format/time";
import { PageHeader } from "@/shell/page-header";
import { StatTile } from "@/shell/stat-tile";
import { ActiveCACard, CreateCACard } from "./ca-card";
import { EpicCard } from "./epic-card";
import { FirmwareCard } from "./firmware-card";
import { trustQuery } from "./queries";
import { ReleasesCard } from "./releases-card";

export function TrustPage() {
  const { data } = useSuspenseQuery(trustQuery);
  const branches = data.releases.flatMap((release) => [release.stable, release.testing]).filter((state) => state !== "none");
  const signed = branches.filter((state) => state === "signed").length;
  return (
    <div className="space-y-4">
      <PageHeader
        title="Trust"
        description="The NixlyOS CA, the Secure Boot chain it anchors and everything Epic needs to approve the kernels."
      />
      {data.active === null && <CreateCACard />}
      {data.active !== null && (
        <>
          <div className="grid gap-4 sm:grid-cols-3">
            <StatTile label="Signed files" value={data.signatures.toLocaleString("en-GB")} hint="Kernels, modules, boot loaders" icon={FileSignature} />
            <StatTile
              label="Releases signed"
              value={`${signed}/${branches.length}`}
              hint="By the active CA"
              icon={ShieldCheck}
              tone={signed === branches.length ? "success" : "warning"}
            />
            <StatTile label="CA expires" value={timeAgo(data.active.notAfter)} hint="Rotate well before" icon={CalendarClock} tone="info" />
          </div>
          <div className="grid gap-4 xl:grid-cols-2">
            <ActiveCACard ca={data.active} history={data.history} />
            <ReleasesCard releases={data.releases} />
          </div>
          <FirmwareCard firmware={data.firmware} />
        </>
      )}
      <EpicCard rules={data.rules} limits={data.limits} />
    </div>
  );
}

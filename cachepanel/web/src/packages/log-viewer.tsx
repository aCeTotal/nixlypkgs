import { useQuery } from "@tanstack/react-query";
import { Spinner } from "@/ui/spinner";
import { buildLogQuery } from "./queries";

export function LogViewer({ versionId, live }: { versionId: number; live: boolean }) {
  const { data, isPending } = useQuery(buildLogQuery(versionId, live));
  if (isPending) return <Spinner className="m-4 text-muted-foreground" />;
  return (
    <div className="max-h-96 overflow-auto rounded-lg border bg-sidebar p-3">
      <pre className="font-mono text-[0.72rem] leading-relaxed whitespace-pre-wrap text-sidebar-foreground">
        {data || "No log yet."}
      </pre>
      <div key={data?.length} ref={(node) => node?.scrollIntoView({ block: "nearest" })} />
    </div>
  );
}

import { useSuspenseQuery } from "@tanstack/react-query";
import { getRouteApi } from "@tanstack/react-router";
import { PageHeader } from "@/shell/page-header";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/ui/tabs";
import { UpdateCard } from "@/update/update-card";
import { FilesView } from "./files-view";
import { HistoryView } from "./history-view";
import { InputsView } from "./inputs-view";
import { KeysCard } from "./keys-card";
import { sourceQuery } from "./queries";
import { RemoteCard } from "./remote-card";
import { parseSourceSearch, type SourceSearch } from "./search";

const route = getRouteApi("/app/source");

export function SourcePage() {
  const search = route.useSearch();
  const navigate = route.useNavigate();
  const go = (change: SourceSearch) => void navigate({ to: "/source", search: (current: SourceSearch) => ({ ...current, ...change }) });
  return (
    <div className="space-y-4">
      <PageHeader title="Source" description="nixlypkgs lives in the panel. Every commit, here or pushed, is built and tested before stable." />
      <Tabs value={search.tab ?? "files"} onValueChange={(tab) => go({ tab: parseSourceSearch({ tab }).tab })}>
        <TabsList>
          <TabsTrigger value="files">Files</TabsTrigger>
          <TabsTrigger value="history">History</TabsTrigger>
          <TabsTrigger value="inputs">Inputs</TabsTrigger>
          <TabsTrigger value="access">Access</TabsTrigger>
        </TabsList>
        <TabsContent value="files">
          <FilesView
            path={search.path ?? ""}
            create={search.create ?? false}
            onOpen={(path) => go({ path: path || undefined, create: undefined })}
            onCreate={(path) => go({ path, create: true })}
            onHistory={(path) => go({ tab: "history", path, commit: undefined })}
          />
        </TabsContent>
        <TabsContent value="history">
          <HistoryView
            path={search.path ?? ""}
            commit={search.commit}
            onPath={(path) => go({ path: path || undefined, commit: undefined })}
            onCommit={(commit) => go({ commit })}
          />
        </TabsContent>
        <TabsContent value="inputs">
          <InputsView />
        </TabsContent>
        <TabsContent value="access" className="space-y-4">
          <Access />
        </TabsContent>
      </Tabs>
    </div>
  );
}

function Access() {
  const { data } = useSuspenseQuery(sourceQuery);
  return (
    <>
      <RemoteCard source={data} />
      <KeysCard keys={data.keys} />
      <UpdateCard />
    </>
  );
}

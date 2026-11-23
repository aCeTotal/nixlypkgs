import { useMutation, useSuspenseQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { ArrowLeft, Save, Undo2 } from "lucide-react";
import { useState } from "react";
import { FileBrowser } from "@/shell/file-browser";
import { PageHeader } from "@/shell/page-header";
import { Button } from "@/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/ui/tabs";
import { CheckBadge } from "./check-badge";
import { ProfileActions } from "./profile-actions";
import { ProfileModules } from "./profile-modules";
import { ProfilePackages } from "./profile-packages";
import { ProfileSettingsForm } from "./profile-settings";
import { ProfileStatus } from "./profile-status";
import { profileQuery, saveProfile, type ProfileDetail, type ProfileSettings } from "./queries";

const route = getRouteApi("/app/profiles/$name");

function settingsOf({ profile, modules, packages }: ProfileDetail): ProfileSettings {
  return {
    name: profile.name,
    title: profile.title,
    description: profile.description,
    platform: profile.platform,
    kernel: profile.kernel,
    pinnedSha: profile.pinnedSha,
    modules: modules.filter((module) => module.selected && !module.required).map((module) => module.id),
    packages,
  };
}

export function ProfilePage() {
  const { name } = route.useParams();
  const { data } = useSuspenseQuery(profileQuery(name));
  return <ProfileEditor key={data.profile.updatedAt} detail={data} />;
}

// Edits stay local until saved.
function ProfileEditor({ detail }: { detail: ProfileDetail }) {
  const navigate = route.useNavigate();
  const initial = settingsOf(detail);
  const [draft, setDraft] = useState(initial);
  const dirty = JSON.stringify(draft) !== JSON.stringify(initial);
  const save = useMutation({
    mutationFn: () => saveProfile(detail.profile.name, draft),
    onSuccess: () => {
      if (draft.name !== detail.profile.name) void navigate({ to: "/profiles/$name", params: { name: draft.name } });
    },
  });
  const update = (change: Partial<ProfileSettings>) => setDraft((current) => ({ ...current, ...change }));
  return (
    <div className="space-y-5 pb-20">
      <Button asChild variant="ghost" size="sm" className="-ml-2">
        <Link to="/profiles">
          <ArrowLeft />
          All profiles
        </Link>
      </Button>
      <PageHeader
        title={detail.profile.title}
        description={<CheckBadge state={detail.profile.checkState} />}
        actions={<ProfileActions profile={detail.profile} />}
      />
      <Tabs defaultValue="modules">
        <TabsList>
          <TabsTrigger value="modules">Modules</TabsTrigger>
          <TabsTrigger value="packages">Packages</TabsTrigger>
          <TabsTrigger value="settings">Settings</TabsTrigger>
          <TabsTrigger value="status">Checks and rollout</TabsTrigger>
          <TabsTrigger value="files">Generated config</TabsTrigger>
        </TabsList>
        <TabsContent value="modules" className="pt-4">
          <ProfileModules detail={detail} draft={draft} update={update} />
        </TabsContent>
        <TabsContent value="packages" className="pt-4">
          <ProfilePackages packages={draft.packages} update={update} />
        </TabsContent>
        <TabsContent value="settings" className="pt-4">
          <ProfileSettingsForm draft={draft} update={update} />
        </TabsContent>
        <TabsContent value="status" className="pt-4">
          <ProfileStatus profile={detail.profile} />
        </TabsContent>
        <TabsContent value="files" className="pt-4">
          <FileBrowser files={detail.files} />
        </TabsContent>
      </Tabs>
      {dirty && (
        <div className="fixed inset-x-0 bottom-0 z-30 flex justify-center p-4">
          <div className="flex items-center gap-3 rounded-xl border bg-popover/95 px-4 py-3 shadow-xl backdrop-blur animate-in slide-in-from-bottom-4">
            <span className="text-sm">Unsaved changes – checked automatically, then land in testing.</span>
            <Button variant="ghost" size="sm" onClick={() => setDraft(initial)}>
              <Undo2 />
              Discard
            </Button>
            <Button size="sm" onClick={() => save.mutate()} disabled={save.isPending}>
              <Save />
              Save
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

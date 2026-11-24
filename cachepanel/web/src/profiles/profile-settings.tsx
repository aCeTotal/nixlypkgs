import { useInfiniteQuery } from "@tanstack/react-query";
import { commitsQuery } from "@/commits/queries";
import { shortSha } from "@/format/sha";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/ui/select";
import { Textarea } from "@/ui/textarea";
import { KernelChoice } from "./kernel-choice";
import { platformLabels, type Platform, type ProfileSettings } from "./queries";

const automatic = "auto";

type ProfileSettingsFormProps = { draft: ProfileSettings; update: (change: Partial<ProfileSettings>) => void };

export function ProfileSettingsForm({ draft, update }: ProfileSettingsFormProps) {
  const { data } = useInfiniteQuery(commitsQuery);
  const commits = (data?.pages[0]?.items ?? []).filter((commit) => commit.evalState === "done");
  return (
    <div className="grid gap-4 xl:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Identity</CardTitle>
          <CardDescription>The ID is written into machine configs; machines follow if it changes.</CardDescription>
        </CardHeader>
        <CardContent>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="title">Name</FieldLabel>
              <Input id="title" value={draft.title} onChange={(event) => update({ title: event.target.value })} />
            </Field>
            <Field>
              <FieldLabel htmlFor="name">ID</FieldLabel>
              <Input id="name" className="font-mono" value={draft.name} onChange={(event) => update({ name: event.target.value })} />
            </Field>
            <Field>
              <FieldLabel htmlFor="description">Description</FieldLabel>
              <Textarea id="description" value={draft.description} onChange={(event) => update({ description: event.target.value })} />
            </Field>
            <Field>
              <FieldLabel>Platform</FieldLabel>
              <Select value={draft.platform} onValueChange={(value) => update({ platform: value as Platform })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(platformLabels).map(([value, label]) => (
                    <SelectItem key={value} value={value}>
                      {label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <FieldDescription>The platform sets the system mode and which modules are suggested.</FieldDescription>
            </Field>
          </FieldGroup>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>nixlypkgs revision</CardTitle>
          <CardDescription>Which nixlypkgs commit (and so which nixpkgs stable) the profile runs.</CardDescription>
        </CardHeader>
        <CardContent>
          <Field>
            <FieldLabel>Pin to commit</FieldLabel>
            <Select value={draft.pinnedSha ?? automatic} onValueChange={(value) => update({ pinnedSha: value === automatic ? null : value })}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={automatic}>Automatic – newest commit with everything built</SelectItem>
                {draft.pinnedSha && !commits.some((commit) => commit.sha === draft.pinnedSha) && (
                  <SelectItem value={draft.pinnedSha}>{shortSha(draft.pinnedSha)}</SelectItem>
                )}
                {commits.map((commit) => (
                  <SelectItem key={commit.sha} value={commit.sha}>
                    <span className="font-mono">{shortSha(commit.sha)}</span> {commit.subject}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <FieldDescription>A pinned commit keeps its builds in the cache until unpinned.</FieldDescription>
          </Field>
        </CardContent>
      </Card>
      <KernelChoice kernel={draft.kernel} settings={draft.kernelSettings} onChange={(kernel, kernelSettings) => update({ kernel, kernelSettings })} />
    </div>
  );
}

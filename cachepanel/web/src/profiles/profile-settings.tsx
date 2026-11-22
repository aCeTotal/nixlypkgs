import { useInfiniteQuery } from "@tanstack/react-query";
import { commitsQuery } from "@/commits/queries";
import { shortSha } from "@/format/sha";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/ui/select";
import { Textarea } from "@/ui/textarea";
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
          <CardTitle>Identitet</CardTitle>
          <CardDescription>ID-en står i maskinenes konfig; endres den, følger maskinene med.</CardDescription>
        </CardHeader>
        <CardContent>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="title">Navn</FieldLabel>
              <Input id="title" value={draft.title} onChange={(event) => update({ title: event.target.value })} />
            </Field>
            <Field>
              <FieldLabel htmlFor="name">ID</FieldLabel>
              <Input id="name" className="font-mono" value={draft.name} onChange={(event) => update({ name: event.target.value })} />
            </Field>
            <Field>
              <FieldLabel htmlFor="description">Beskrivelse</FieldLabel>
              <Textarea id="description" value={draft.description} onChange={(event) => update({ description: event.target.value })} />
            </Field>
            <Field>
              <FieldLabel>Plattform</FieldLabel>
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
              <FieldDescription>Plattformen styrer systemmodus og hvilke moduler som foreslås.</FieldDescription>
            </Field>
          </FieldGroup>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Revisjon av nixlypkgs</CardTitle>
          <CardDescription>Hvilken commit av nixlypkgs (og dermed nixpkgs stable) profilen kjører.</CardDescription>
        </CardHeader>
        <CardContent>
          <Field>
            <FieldLabel>Lås til commit</FieldLabel>
            <Select value={draft.pinnedSha ?? automatic} onValueChange={(value) => update({ pinnedSha: value === automatic ? null : value })}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={automatic}>Automatisk – nyeste commit der alt er bygget</SelectItem>
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
            <FieldDescription>En låst commit beholder sine bygg i cachen til låsen fjernes.</FieldDescription>
          </Field>
        </CardContent>
      </Card>
    </div>
  );
}

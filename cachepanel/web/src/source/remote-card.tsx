import { GitBranch, Upload } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { CommandLine } from "./command-line";
import type { Source } from "./queries";

export function RemoteCard({ source }: { source: Source }) {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <GitBranch className="size-4 text-primary" />
            Clone
          </CardTitle>
          <CardDescription>Anyone can read; machines lock each release from here.</CardDescription>
        </CardHeader>
        <CardContent>
          <CommandLine command={`git clone ${source.clone} nixlypkgs`} />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Upload className="size-4 text-primary" />
            Push
          </CardTitle>
          <CardDescription>Keys below may push. History only moves forward: no force pushes, no deleted branches.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {source.remote ? (
            <>
              <CommandLine command={`git remote set-url origin ${source.remote}`} />
              <CommandLine command="git push origin main" />
            </>
          ) : (
            <p className="text-sm text-muted-foreground">Set source.sshRemote in the module to push over SSH.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

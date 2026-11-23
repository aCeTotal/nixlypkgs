import { useQuery } from "@tanstack/react-query";
import { Copy, KeyRound } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { publishingQuery } from "./queries";

export function DeployKey() {
  const { data } = useQuery(publishingQuery);
  if (!data) return null;
  if (!data.publicKey) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <KeyRound className="size-4 text-muted-foreground" />
            Publishing is not set up
          </CardTitle>
          <CardDescription>Set publish.remote in the module to let the panel push to nixlypkgs.</CardDescription>
        </CardHeader>
      </Card>
    );
  }
  const copy = () => void navigator.clipboard.writeText(data.publicKey ?? "").then(() => toast.success("Key copied"));
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <KeyRound className="size-4 text-primary" />
          Deploy key
        </CardTitle>
        <CardDescription>
          The panel pushes to <span className="font-mono text-foreground">{data.remote}</span>. Add the key under Settings → Deploy
          keys on GitHub, with write access.
        </CardDescription>
        <CardAction>
          <Button size="sm" variant="outline" onClick={copy}>
            <Copy />
            Copy
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent>
        <pre className="overflow-x-auto rounded-lg bg-muted/50 p-3 font-mono text-xs">{data.publicKey}</pre>
      </CardContent>
    </Card>
  );
}

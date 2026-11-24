import { Hammer } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { CheckBadge } from "./check-badge";
import type { StableCheck } from "./queries";

export function StableProgress({ checks }: { checks: StableCheck[] }) {
  if (checks.length === 0) return null;
  return (
    <Card className="border-info/40">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Hammer className="size-4 text-info" />
          Building stable
        </CardTitle>
        <CardDescription>Approved changes are built on every reference machine and signed before stable moves.</CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="space-y-2">
          {checks.map((check) => (
            <li key={check.id} className="space-y-1.5">
              <div className="flex items-center justify-between gap-3 text-sm">
                <span className="font-medium">{check.title}</span>
                <CheckBadge state={check.state} />
              </div>
              {check.error && (
                <pre className="max-h-40 overflow-auto rounded-md bg-muted/60 p-2 font-mono text-xs whitespace-pre-wrap">{check.error}</pre>
              )}
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}

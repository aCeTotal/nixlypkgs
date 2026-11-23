import { CircleAlert, CircleCheck, Download, Gamepad2 } from "lucide-react";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import type { Trust } from "./queries";

export function EpicCard({ rules, limits }: Pick<Trust, "rules" | "limits">) {
  const areas = [...new Set(rules.map((rule) => rule.area))];
  return (
    <Card className="relative overflow-hidden">
      <div className="pointer-events-none absolute -bottom-28 -left-28 size-64 rounded-full bg-info/10 blur-3xl" />
      <CardHeader className="relative">
        <CardTitle className="flex items-center gap-2">
          <Gamepad2 className="size-4 text-info" />
          Easy Anti-Cheat review
        </CardTitle>
        <CardDescription>
          Epic approves a kernel by the key that signs it. Send them the bundle; it holds the CA certificate and the policy below.
        </CardDescription>
        <CardAction>
          <Button asChild size="sm">
            <a href="/api/trust/epic.zip" download>
              <Download />
              Submission bundle
            </a>
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent className="relative grid gap-5 lg:grid-cols-2">
        <div className="space-y-4">
          {areas.map((area) => (
            <div key={area}>
              <p className="mb-1.5 text-xs font-semibold tracking-wide text-muted-foreground uppercase">{area}</p>
              <ul className="space-y-1.5">
                {rules
                  .filter((rule) => rule.area === area)
                  .map((rule) => (
                    <li key={rule.text} className="flex gap-2 text-sm">
                      <CircleCheck className="mt-0.5 size-4 shrink-0 text-success" />
                      {rule.text}
                    </li>
                  ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="space-y-3">
          <p className="text-xs font-semibold tracking-wide text-muted-foreground uppercase">Not covered by signatures</p>
          <ul className="space-y-2">
            {limits.map((limit) => (
              <li key={limit} className="flex gap-2 rounded-lg bg-warning-soft/60 p-2.5 text-sm">
                <CircleAlert className="mt-0.5 size-4 shrink-0 text-warning-foreground" />
                {limit}
              </li>
            ))}
          </ul>
          <p className="text-xs text-muted-foreground">
            Keep these honest in the submission: Epic re-reviews when the CA rotates, so send the new bundle after every rotation.
          </p>
        </div>
      </CardContent>
    </Card>
  );
}

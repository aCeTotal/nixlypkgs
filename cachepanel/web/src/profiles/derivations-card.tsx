import { useMutation } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { ArrowRight, CircleCheck, Package } from "lucide-react";
import { toast } from "sonner";
import { timeAgo } from "@/format/time";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { approve, type AwaitingDerivation } from "./queries";

export function DerivationsCard({ derivations }: { derivations: AwaitingDerivation[] }) {
  const ship = useMutation({
    mutationFn: (chosen: AwaitingDerivation[]) => approve({ profiles: [], derivations: chosen }),
    onSuccess: (_, chosen) => toast.success(chosen.length === 1 ? `${chosen[0].attr} approved for stable` : "Derivations approved for stable"),
  });
  if (derivations.length === 0) {
    return (
      <Card className="bg-muted/30">
        <CardContent className="flex items-center gap-3 text-sm">
          <CircleCheck className="size-5 shrink-0 text-success" />
          <p>
            <span className="font-medium">Stable has every derivation testing has.</span>{" "}
            <span className="text-muted-foreground">New versions wait here, one by one.</span>
          </p>
        </CardContent>
      </Card>
    );
  }
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Package className="size-4 text-primary" />
          Derivations
        </CardTitle>
        <CardDescription>Each version moves to stable on its own. Stable is rebuilt and signed before machines get it.</CardDescription>
        <CardAction>
          <Button size="sm" variant="outline" onClick={() => ship.mutate(derivations)} disabled={ship.isPending}>
            <CircleCheck />
            Approve all {derivations.length}
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent>
        <ul className="divide-y">
          {derivations.map((derivation) => (
            <li key={`${derivation.attr}-${derivation.version}`} className="flex flex-wrap items-center gap-3 py-2.5 first:pt-0 last:pb-0">
              <div className="min-w-0 flex-1">
                <Link to="/packages/$attr" params={{ attr: derivation.attr }} className="truncate font-mono text-sm font-medium hover:underline">
                  {derivation.attr}
                </Link>
                <p className="flex items-center gap-1.5 truncate text-xs text-muted-foreground">
                  <span className="truncate">{derivation.stableName ?? "follows the base"}</span>
                  <ArrowRight className="size-3 shrink-0" />
                  <span className="truncate text-foreground">{derivation.name}</span>
                </p>
              </div>
              <span className="shrink-0 text-xs text-muted-foreground">{timeAgo(derivation.builtAt)}</span>
              <Button size="sm" onClick={() => ship.mutate([derivation])} disabled={ship.isPending}>
                Approve
              </Button>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}

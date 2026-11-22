import { useRouter, type ErrorComponentProps } from "@tanstack/react-router";
import { TriangleAlert } from "lucide-react";
import { Button } from "@/ui/button";
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/ui/empty";

export function RouteError({ error, reset }: ErrorComponentProps) {
  const router = useRouter();
  return (
    <Empty className="min-h-[60vh]">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <TriangleAlert />
        </EmptyMedia>
        <EmptyTitle>Noe gikk galt</EmptyTitle>
        <EmptyDescription>{error instanceof Error ? error.message : "Ukjent feil"}</EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Button
          onClick={() => {
            reset();
            void router.invalidate();
          }}
        >
          Prøv igjen
        </Button>
      </EmptyContent>
    </Empty>
  );
}

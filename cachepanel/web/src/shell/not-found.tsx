import { Link } from "@tanstack/react-router";
import { Compass } from "lucide-react";
import { Button } from "@/ui/button";
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/ui/empty";

export function NotFound() {
  return (
    <Empty className="min-h-[60vh]">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <Compass />
        </EmptyMedia>
        <EmptyTitle>Fant ikke siden</EmptyTitle>
        <EmptyDescription>Lenken kan være feil, eller siden er flyttet.</EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Button asChild>
          <Link to="/">Til oversikten</Link>
        </Button>
      </EmptyContent>
    </Empty>
  );
}

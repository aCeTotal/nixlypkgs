import { useMatches } from "@tanstack/react-router";
import { useEffect } from "react";
import { Separator } from "@/ui/separator";
import { SidebarTrigger } from "@/ui/sidebar";
import { LiveIndicator } from "./live-indicator";
import { ThemeSwitch } from "./theme-switch";
import { UserMenu } from "./user-menu";

export function TopBar() {
  const title = useMatches({ select: (matches) => matches.findLast((match) => match.staticData.title)?.staticData.title });

  useEffect(() => {
    document.title = title ? `${title} · Nixly Panel` : "Nixly Panel";
  }, [title]);

  return (
    <header className="sticky top-0 z-20 flex h-14 shrink-0 items-center gap-3 border-b bg-background/85 px-4 backdrop-blur">
      <SidebarTrigger className="-ml-1" />
      <Separator orientation="vertical" className="h-5 data-vertical:self-center max-sm:hidden" />
      <h2 className="truncate text-base font-medium text-muted-foreground max-sm:hidden">{title}</h2>
      <div className="ml-auto flex items-center gap-2">
        <LiveIndicator />
        <ThemeSwitch />
        <UserMenu />
      </div>
    </header>
  );
}

import { Link, useLocation } from "@tanstack/react-router";
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarRail,
} from "@/ui/sidebar";
import { navigation, type NavItem } from "./navigation";

function isActive(pathname: string, to: NavItem["to"]) {
  return to === "/" ? pathname === "/" : pathname === to || pathname.startsWith(`${to}/`);
}

export function AppSidebar() {
  const pathname = useLocation({ select: (location) => location.pathname });
  return (
    <Sidebar collapsible="icon">
      <SidebarHeader>
        <Link to="/" className="flex items-center gap-2.5 px-1.5 py-1">
          <img src="/favicon.svg" alt="" className="size-9 shrink-0 rounded-xl shadow-md shadow-primary/30" />
          <span className="truncate leading-tight group-data-[collapsible=icon]:hidden">
            <span className="block font-semibold tracking-tight">Nixly Panel</span>
            <span className="block text-xs text-muted-foreground">Cache · profiler · pakker</span>
          </span>
        </Link>
      </SidebarHeader>
      <SidebarContent>
        {navigation.map((group) => (
          <SidebarGroup key={group.label}>
            <SidebarGroupLabel>{group.label}</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {group.items.map((item) => (
                  <SidebarMenuItem key={item.to}>
                    <SidebarMenuButton asChild isActive={isActive(pathname, item.to)} tooltip={item.label}>
                      <Link to={item.to}>
                        <item.icon />
                        <span>{item.label}</span>
                      </Link>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        ))}
      </SidebarContent>
      <SidebarRail />
    </Sidebar>
  );
}

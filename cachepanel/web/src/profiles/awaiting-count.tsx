import { useQuery } from "@tanstack/react-query";
import { SidebarMenuBadge } from "@/ui/sidebar";
import { approvalQuery } from "./queries";

export function AwaitingCount() {
  const { data } = useQuery(approvalQuery);
  const count = (data?.profiles.length ?? 0) + (data?.derivations.length ?? 0);
  if (count === 0) return null;
  return <SidebarMenuBadge className="bg-warning-soft text-warning-foreground">{count}</SidebarMenuBadge>;
}

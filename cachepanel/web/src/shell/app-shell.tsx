import { Outlet } from "@tanstack/react-router";
import { Suspense } from "react";
import { useLiveUpdates } from "@/api/live-updates";
import { SidebarInset, SidebarProvider } from "@/ui/sidebar";
import { AppSidebar } from "./app-sidebar";
import { PageLoading } from "./page-loading";
import { TopBar } from "./top-bar";

export function AppShell() {
  useLiveUpdates();
  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset className="min-w-0">
        <TopBar />
        <main className="flex-1 p-4 md:p-6">
          <Suspense fallback={<PageLoading />}>
            <Outlet />
          </Suspense>
        </main>
      </SidebarInset>
    </SidebarProvider>
  );
}

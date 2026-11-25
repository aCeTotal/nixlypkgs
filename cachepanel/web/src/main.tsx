import { QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider } from "@tanstack/react-router";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { queryClient } from "@/api/query-client";
import { ThemeProvider } from "@/shell/theme";
import { Toaster } from "@/ui/sonner";
import { TooltipProvider } from "@/ui/tooltip";
import { router } from "./router";
import "./styles.css";

const reloadedAt = "nixly-reloaded-at";
const reloadPause = 10_000;

// A deploy replaced the chunks this page knows.
window.addEventListener("vite:preloadError", (event) => {
  if (Date.now() - Number(sessionStorage.getItem(reloadedAt) ?? 0) < reloadPause) return;
  event.preventDefault();
  sessionStorage.setItem(reloadedAt, String(Date.now()));
  window.location.reload();
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider>
      <QueryClientProvider client={queryClient}>
        <TooltipProvider delayDuration={300}>
          <RouterProvider router={router} />
          <Toaster richColors position="top-right" />
        </TooltipProvider>
      </QueryClientProvider>
    </ThemeProvider>
  </StrictMode>,
);

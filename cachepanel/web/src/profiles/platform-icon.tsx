import { Monitor, Server, Tv } from "lucide-react";
import type { Platform } from "./queries";

const icons = { desktop: Monitor, htpc: Tv, server: Server } as const;

export function PlatformIcon({ platform, className }: { platform: Platform; className?: string }) {
  const Icon = icons[platform];
  return <Icon className={className} />;
}

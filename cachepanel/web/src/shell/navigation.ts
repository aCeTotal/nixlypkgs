import type { LinkProps } from "@tanstack/react-router";
import { Blocks, GitCommitVertical, LayoutDashboard, Layers, Package, PackagePlus, type LucideIcon } from "lucide-react";

export type NavItem = {
  label: string;
  to: NonNullable<LinkProps["to"]>;
  icon: LucideIcon;
};

export type NavGroup = { label: string; items: NavItem[] };

export const navigation: NavGroup[] = [
  { label: "Drift", items: [{ label: "Oversikt", to: "/", icon: LayoutDashboard }] },
  {
    label: "Systemer",
    items: [
      { label: "Profiler", to: "/profiles", icon: Layers },
      { label: "Moduler", to: "/modules", icon: Blocks },
    ],
  },
  {
    label: "nixlypkgs",
    items: [
      { label: "Pakker", to: "/packages", icon: Package },
      { label: "Nye pakker", to: "/recipes", icon: PackagePlus },
      { label: "Commits", to: "/commits", icon: GitCommitVertical },
    ],
  },
];

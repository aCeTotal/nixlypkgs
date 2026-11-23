import type { LinkProps } from "@tanstack/react-router";
import type { ComponentType } from "react";
import { Blocks, FlaskConical, GitCommitVertical, LayoutDashboard, Layers, Package, PackagePlus, ShieldCheck, type LucideIcon } from "lucide-react";
import { AwaitingCount } from "@/profiles/awaiting-count";

export type NavItem = {
  label: string;
  to: NonNullable<LinkProps["to"]>;
  icon: LucideIcon;
  badge?: ComponentType;
};

export type NavGroup = { label: string; items: NavItem[] };

export const navigation: NavGroup[] = [
  { label: "Operations", items: [{ label: "Overview", to: "/", icon: LayoutDashboard }] },
  {
    label: "Systems",
    items: [
      { label: "Profiles", to: "/profiles", icon: Layers },
      { label: "Testing", to: "/testing", icon: FlaskConical, badge: AwaitingCount },
      { label: "Trust", to: "/trust", icon: ShieldCheck },
      { label: "Modules", to: "/modules", icon: Blocks },
    ],
  },
  {
    label: "nixlypkgs",
    items: [
      { label: "Derivations", to: "/packages", icon: Package },
      { label: "Add derivation", to: "/recipes", icon: PackagePlus },
      { label: "Commits", to: "/commits", icon: GitCommitVertical },
    ],
  },
];

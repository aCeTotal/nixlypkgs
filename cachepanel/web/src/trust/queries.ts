import { queryOptions } from "@tanstack/react-query";
import { api } from "@/api/http";
import type { Platform } from "@/profiles/queries";

export type CA = {
  id: number;
  subject: string;
  fingerprint: string;
  certPem: string;
  notAfter: string;
  createdAt: string;
  retiredAt: string | null;
};

export type FirmwareVariable = "PK" | "KEK" | "db";

export type Database = { variable: FirmwareVariable; certs: { subject: string; owner: string }[] };

export type SignatureState = "signed" | "old" | "unsigned" | "none";

export type Release = { profile: string; title: string; platform: Platform; stable: SignatureState; testing: SignatureState };

export type Trust = {
  active: CA | null;
  history: CA[];
  signatures: number;
  firmware: Database[];
  releases: Release[];
  rules: { area: string; text: string }[];
  limits: string[];
};

export const trustQuery = queryOptions({ queryKey: ["trust"], queryFn: () => api<Trust>("/trust") });

export const createCA = () => api<CA>("/trust/ca", { method: "POST" });

export const fingerprintPairs = (fingerprint: string) => fingerprint.toUpperCase().match(/.{2}/g)?.join(":") ?? fingerprint;

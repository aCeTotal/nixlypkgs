import { Cpu, Lock } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { cn } from "@/ui/cn";
import type { Database, FirmwareVariable } from "./queries";

const roles: Record<FirmwareVariable, string> = {
  PK: "Platform key: who may change KEK",
  KEK: "Key exchange keys: who may change db",
  db: "Allowed signers: what may boot",
};

const steps = [
  { command: "nixlyos-secureboot status", text: "Shows the firmware keys and whether this machine follows the panel." },
  { command: "sudo nixlyos-secureboot enroll", text: "Firmware in setup mode: writes PK, then KEK and db. Only the PK is trusted on sight, and it must match the CA this system was built with." },
  { command: "sudo nixlyos-secureboot update", text: "After a rotation: the old CA signs the move to the new one, so setup mode is never needed again." },
];

export function FirmwareCard({ firmware }: { firmware: Database[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Lock className="size-4 text-primary" />
          Secure Boot chain
        </CardTitle>
        <CardDescription>
          The panel signs every firmware key update. Machines hold no signing key, so root on a machine cannot add its own.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-5 lg:grid-cols-2">
        <ul className="space-y-3">
          {firmware.map((database) => (
            <li key={database.variable} className="rounded-lg border bg-card/60 p-3">
              <p className="flex items-baseline gap-2">
                <span className="font-mono text-sm font-semibold">{database.variable}</span>
                <span className="text-xs text-muted-foreground">{roles[database.variable]}</span>
              </p>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {database.certs.map((cert) => (
                  <span
                    key={`${cert.owner}-${cert.subject}`}
                    className={cn(
                      "rounded-md px-1.5 py-0.5 text-[0.7rem]",
                      cert.owner === "NixlyOS" ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground",
                    )}
                  >
                    {cert.subject}
                  </span>
                ))}
              </div>
            </li>
          ))}
        </ul>
        <div className="space-y-3">
          <p className="flex items-center gap-2 text-sm font-medium">
            <Cpu className="size-4 text-muted-foreground" />
            On each machine
          </p>
          <ol className="space-y-3">
            {steps.map((step, index) => (
              <li key={step.command} className="flex gap-3 text-sm">
                <span className="grid size-6 shrink-0 place-items-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
                  {index + 1}
                </span>
                <div className="min-w-0 space-y-1">
                  <code className="block rounded-md bg-muted/60 px-2 py-1 font-mono text-xs">{step.command}</code>
                  <p className="text-xs text-muted-foreground">{step.text}</p>
                </div>
              </li>
            ))}
          </ol>
          <p className="text-xs text-muted-foreground">
            Microsoft's keys stay in KEK and db so GPU option ROMs and Windows keep booting.
          </p>
        </div>
      </CardContent>
    </Card>
  );
}

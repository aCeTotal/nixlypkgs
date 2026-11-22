import { useQuery } from "@tanstack/react-query";
import { FileCode } from "lucide-react";
import { shortSha } from "@/format/sha";
import { Button } from "@/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/ui/dialog";
import { Spinner } from "@/ui/spinner";
import { NixEditor } from "./nix-editor";
import { catalogSourceQuery, type CatalogModule } from "./queries";

function Source({ name }: { name: string }) {
  const { data } = useQuery(catalogSourceQuery(name));
  if (!data) return <Spinner className="m-6 text-muted-foreground" />;
  return (
    <div className="space-y-2">
      <p className="font-mono text-xs text-muted-foreground">
        {data.path} @ {shortSha(data.commit)}
      </p>
      <div className="h-[60vh]">
        <NixEditor value={data.source} readOnly />
      </div>
    </div>
  );
}

// Repository modules change through git.
export function SourceDialog({ module }: { module: CatalogModule }) {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button size="sm" variant="ghost">
          <FileCode />
          Kilde
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-4xl">
        <DialogHeader>
          <DialogTitle>{module.title}</DialogTitle>
          <DialogDescription>Skrivebeskyttet – endres i nixlypkgs og kommer inn med neste commit.</DialogDescription>
        </DialogHeader>
        <Source name={module.name} />
      </DialogContent>
    </Dialog>
  );
}

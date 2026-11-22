import { FileCode } from "lucide-react";
import { useState } from "react";
import { Card, CardContent } from "@/ui/card";
import { cn } from "@/ui/cn";

export function FileBrowser({ files }: { files: { path: string; content: string }[] }) {
  const [current, setCurrent] = useState(files[0]?.path ?? "");
  const shown = files.find((file) => file.path === current);
  if (files.length === 0) return <p className="text-sm text-muted-foreground">Ingen filer ennå.</p>;
  return (
    <Card className="overflow-hidden py-0">
      <CardContent className="grid p-0 md:grid-cols-[16rem_1fr]">
        <nav className="border-b bg-muted/30 p-2 md:border-r md:border-b-0">
          {files.map((file) => (
            <button
              key={file.path}
              type="button"
              onClick={() => setCurrent(file.path)}
              className={cn(
                "flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left font-mono text-xs hover:bg-muted",
                file.path === current && "bg-primary/10 text-primary",
              )}
            >
              <FileCode className="size-3.5 shrink-0" />
              <span className="truncate">{file.path}</span>
            </button>
          ))}
        </nav>
        <pre className="max-h-[36rem] overflow-auto p-4 font-mono text-xs leading-relaxed">{shown?.content}</pre>
      </CardContent>
    </Card>
  );
}

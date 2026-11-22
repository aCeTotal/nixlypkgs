import { FileUp, X } from "lucide-react";
import { useState } from "react";
import { formatBytes } from "@/format/bytes";
import { Button } from "@/ui/button";
import { cn } from "@/ui/cn";

type DropZoneProps = { multiple: boolean; files: File[]; onFiles: (files: File[]) => void; hint: string };

// Input covers the zone for drops.
export function DropZone({ multiple, files, onFiles, hint }: DropZoneProps) {
  const [over, setOver] = useState(false);
  const add = (picked: FileList | null) => {
    const list = Array.from(picked ?? []);
    setOver(false);
    onFiles(multiple ? [...files.filter((file) => !list.some((next) => next.name === file.name)), ...list] : list.slice(0, 1));
  };
  return (
    <div className="space-y-3">
      <div
        className={cn(
          "relative flex flex-col items-center gap-2 rounded-xl border-2 border-dashed p-8 text-center transition-colors hover:border-primary/50 hover:bg-primary/5",
          over && "border-primary bg-primary/10",
        )}
      >
        <FileUp className="size-8 text-primary" />
        <span className="font-medium">Slipp {multiple ? "filene" : "filen"} her, eller klikk for å velge</span>
        <span className="text-sm text-muted-foreground">{hint}</span>
        <input
          type="file"
          multiple={multiple}
          aria-label={multiple ? "Velg filer" : "Velg fil"}
          className="absolute inset-0 cursor-pointer opacity-0"
          onDragEnter={() => setOver(true)}
          onDragLeave={() => setOver(false)}
          onChange={(event) => add(event.target.files)}
        />
      </div>
      {files.length > 0 && (
        <ul className="divide-y rounded-lg border">
          {files.map((file) => (
            <li key={file.name} className="flex items-center gap-3 px-3 py-2 text-sm">
              <span className="min-w-0 flex-1 truncate font-mono">{file.name}</span>
              <span className="text-xs text-muted-foreground tabular-nums">{formatBytes(file.size)}</span>
              <Button
                type="button"
                variant="ghost"
                size="icon-sm"
                aria-label={`Fjern ${file.name}`}
                onClick={() => onFiles(files.filter((other) => other !== file))}
              >
                <X />
              </Button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

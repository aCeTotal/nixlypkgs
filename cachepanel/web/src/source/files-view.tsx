import { FolderGit2 } from "lucide-react";
import { Card, CardContent } from "@/ui/card";
import { FileEditor } from "./file-editor";
import { FileTree } from "./file-tree";
import { NewFileDialog } from "./new-file-dialog";
import { QuickOpen } from "./quick-open";

type FilesViewProps = {
  path: string;
  create: boolean;
  onOpen: (path: string) => void;
  onCreate: (path: string) => void;
  onHistory: (path: string) => void;
};

export function FilesView({ path, create, onOpen, onCreate, onHistory }: FilesViewProps) {
  const folder = path.slice(0, Math.max(path.lastIndexOf("/"), 0));
  return (
    <Card className="overflow-hidden py-0">
      <CardContent className="grid p-0 lg:grid-cols-[18rem_1fr]">
        <aside className="flex max-h-[75vh] flex-col border-b bg-muted/20 lg:border-r lg:border-b-0">
          <div className="flex items-center justify-between gap-2 border-b px-3 py-2">
            <span className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
              <FolderGit2 className="size-3.5" />
              main
            </span>
            <span className="flex items-center gap-1">
              <span className="hidden text-[0.65rem] text-muted-foreground xl:inline">Ctrl+P</span>
              <NewFileDialog folder={folder} onCreate={onCreate} />
            </span>
            <QuickOpen onOpen={onOpen} />
          </div>
          <div className="overflow-y-auto p-1">
            <FileTree selected={path} onSelect={onOpen} />
          </div>
        </aside>
        <div className="h-[75vh] min-w-0 p-4">
          {path ? (
            <FileEditor path={path} create={create} onCommitted={onOpen} onHistory={() => onHistory(path)} />
          ) : (
            <div className="grid h-full place-items-center rounded-lg border border-dashed text-sm text-muted-foreground">
              Pick a file, or start a new one.
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

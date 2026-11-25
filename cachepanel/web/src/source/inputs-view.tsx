import { useMutation, useQuery } from "@tanstack/react-query";
import { LoaderCircle, RefreshCw, type LucideProps } from "lucide-react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Skeleton } from "@/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/ui/table";
import { CommitButton } from "./commit-button";
import { inputsQuery, updateInputs } from "./queries";

function Spinning(props: LucideProps) {
  return <LoaderCircle {...props} className="animate-spin" />;
}

export function InputsView() {
  const { data } = useQuery(inputsQuery);
  const update = useMutation({
    mutationFn: ({ inputs, message }: { inputs: string[]; message: string }) => updateInputs(data?.head ?? "", inputs, message),
    onSuccess: ({ sha }, { inputs }) =>
      toast.success(`${inputs.length === 0 ? "Every input" : inputs.join(", ")} updated in ${shortSha(sha)}; testing builds it next`),
  });
  // One update at a time.
  const busy = (name: string) => update.isPending && (update.variables.inputs.length === 0 || update.variables.inputs.includes(name));
  return (
    <Card>
      <CardHeader>
        <CardTitle>Flake inputs</CardTitle>
        <CardDescription>
          Each update locks the newest revision and commits flake.lock. Testing builds whatever changed before stable can take it.
        </CardDescription>
        <CardAction>
          <CommitButton
            icon={busy("") ? Spinning : RefreshCw}
            variant="outline"
            title="Update every input"
            label="Update all"
            suggestion="flake.lock: update every input"
            pending={update.isPending}
            disabled={!data}
            onCommit={(message) => update.mutate({ inputs: [], message })}
          />
        </CardAction>
      </CardHeader>
      <CardContent>
        {!data && <Skeleton className="h-64" />}
        {data && (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Input</TableHead>
                <TableHead>Source</TableHead>
                <TableHead>Locked</TableHead>
                <TableHead className="w-0" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.inputs.map((input) => (
                <TableRow key={input.name}>
                  <TableCell className="font-mono text-xs font-medium">{input.name}</TableCell>
                  <TableCell className="max-w-80 truncate text-xs text-muted-foreground" title={input.source}>
                    {input.source}
                    {input.ref && <span className="ml-1.5 rounded bg-muted px-1.5 py-0.5 font-mono text-foreground">{input.ref}</span>}
                  </TableCell>
                  <TableCell className="text-xs whitespace-nowrap">
                    {input.rev && <span className="mr-2 font-mono">{shortSha(input.rev)}</span>}
                    <span className="text-muted-foreground">{input.modified ? timeAgo(input.modified) : "content hash"}</span>
                  </TableCell>
                  <TableCell>
                    <CommitButton
                      icon={busy(input.name) ? Spinning : RefreshCw}
                      variant="ghost"
                      title={`Update ${input.name}`}
                      label="Update"
                      suggestion={`flake.lock: update ${input.name}`}
                      pending={update.isPending}
                      onCommit={(message) => update.mutate({ inputs: [input.name], message })}
                    />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

import { useMutation, useQuery } from "@tanstack/react-query";
import { LoaderCircle, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { shortSha } from "@/format/sha";
import { timeAgo } from "@/format/time";
import { Button } from "@/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/ui/card";
import { Skeleton } from "@/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/ui/table";
import { inputsQuery, updateInputs } from "./queries";

export function InputsView() {
  const { data } = useQuery(inputsQuery);
  const update = useMutation({
    mutationFn: (inputs: string[]) => updateInputs(data?.head ?? "", inputs),
    onSuccess: ({ sha }, inputs) =>
      toast.success(`${inputs.length === 0 ? "Every input" : inputs.join(", ")} updated in ${shortSha(sha)}; testing builds it next`),
  });
  // One update at a time; the row shows which.
  const busy = (name: string) => update.isPending && (update.variables.length === 0 || update.variables.includes(name));
  return (
    <Card>
      <CardHeader>
        <CardTitle>Flake inputs</CardTitle>
        <CardDescription>
          Each update locks the newest revision and commits flake.lock. Testing builds whatever changed before stable can take it.
        </CardDescription>
        <CardAction>
          <Button size="sm" variant="outline" onClick={() => update.mutate([])} disabled={!data || update.isPending}>
            <RefreshCw className={update.isPending && update.variables.length === 0 ? "animate-spin" : undefined} />
            Update all
          </Button>
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
                    <Button size="sm" variant="ghost" onClick={() => update.mutate([input.name])} disabled={update.isPending}>
                      {busy(input.name) ? <LoaderCircle className="animate-spin" /> : <RefreshCw />}
                      Update
                    </Button>
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

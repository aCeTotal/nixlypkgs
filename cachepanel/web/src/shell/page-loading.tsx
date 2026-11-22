import { Spinner } from "@/ui/spinner";

export function PageLoading() {
  return (
    <div className="grid min-h-[50vh] place-items-center">
      <Spinner className="size-6 text-muted-foreground" />
    </div>
  );
}

import { useRecipeLog } from "./use-recipe-log";

export function RecipeLog({ id, live }: { id: number; live: boolean }) {
  const text = useRecipeLog(id, live);
  return (
    <div className="h-[28rem] overflow-auto rounded-lg border bg-sidebar p-3">
      <pre className="font-mono text-[0.72rem] leading-relaxed whitespace-pre-wrap text-sidebar-foreground">
        {text || (live ? "Starting the build …" : "No log yet. Press “Test build”.")}
      </pre>
      {live && <div key={text.length} ref={(node) => node?.scrollIntoView({ block: "nearest" })} />}
    </div>
  );
}

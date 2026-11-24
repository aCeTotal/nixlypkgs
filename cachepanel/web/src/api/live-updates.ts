import { useEffect } from "react";
import { forgetProgress, setProgress, type Progress } from "@/builds/progress-store";
import { invalidateSoon, onEvent } from "./realtime";

// Maps server events onto queries.
const invalidations: Record<string, (data: Record<string, unknown>) => unknown[][]> = {
  "version.changed": (data) => [["overview"], ["packages"], ["package", data.attr], ["build-log", data.id], ["profiles"]],
  "package.changed": (data) => [["overview"], ["packages"], ["package", data.attr], ["profiles"]],
  "commit.changed": () => [["commits"], ["overview"]],
  "watcher.changed": () => [["overview"]],
  "profile.changed": () => [["profiles"], ["profile"], ["commits"], ["trust"], ["packages"], ["package"]],
  "trust.changed": () => [["trust"]],
  "module.changed": () => [["modules"], ["module"], ["profile"]],
  "recipe.changed": (data) => [["recipes"], ["recipe", data.id]],
};

export function useLiveUpdates() {
  useEffect(() => {
    const stops = Object.entries(invalidations).map(([type, keys]) =>
      onEvent<Record<string, unknown>>(type, (data) => keys(data ?? {}).forEach(invalidateSoon)),
    );
    stops.push(onEvent<Progress>("build.progress", setProgress));
    stops.push(onEvent<{ id: number }>("version.changed", (data) => forgetProgress(data.id)));
    return () => stops.forEach((stop) => stop());
  }, []);
}

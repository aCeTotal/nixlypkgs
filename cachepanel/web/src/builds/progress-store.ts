import { useSyncExternalStore } from "react";

export type Counter = { done: number; expected: number; running: number; failed: number };

export type Progress = {
  versionId: number;
  attr: string;
  name: string;
  builds: Counter;
  paths: Counter;
  activity: string;
  phase: string;
  line: string;
  startedAt: string;
  expectedSeconds: number;
};

const live = new Map<number, Progress>();
const watchers = new Set<() => void>();
let revision = 0;

function changed() {
  revision++;
  watchers.forEach((notify) => notify());
}

export function setProgress(progress: Progress) {
  live.set(progress.versionId, progress);
  changed();
}

// Server snapshots replace stale entries.
export function seedProgress(snapshot: Progress[]) {
  live.clear();
  snapshot.forEach((progress) => live.set(progress.versionId, progress));
  changed();
}

export function forgetProgress(versionId: number) {
  if (live.delete(versionId)) changed();
}

function subscribe(notify: () => void) {
  watchers.add(notify);
  return () => void watchers.delete(notify);
}

export function useProgress(versionId: number) {
  useSyncExternalStore(subscribe, () => revision);
  return live.get(versionId);
}

export function useAllProgress() {
  useSyncExternalStore(subscribe, () => revision);
  return [...live.values()].toSorted((a, b) => a.startedAt.localeCompare(b.startedAt));
}

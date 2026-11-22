import { useEffect, useEffectEvent, useSyncExternalStore } from "react";
import type { QueryKey } from "@tanstack/react-query";
import { queryClient } from "./query-client";

type Message = { type: string; data: unknown };
type Status = "connecting" | "open" | "closed";

const maxRetryDelay = 30_000;
const refetchDebounce = 400;

const listeners = new Set<(message: Message) => void>();
const watchers = new Set<() => void>();
const pending = new Map<string, number>();
let status: Status = "closed";
let socket: WebSocket | null = null;
let retryDelay = 1_000;
let retryTimer: number | undefined;
let wanted = false;
let connectedBefore = false;

function setStatus(next: Status) {
  status = next;
  watchers.forEach((notify) => notify());
}

export function onEvent<T>(type: string, handler: (data: T) => void) {
  const listener = (message: Message) => {
    if (message.type === type) handler(message.data as T);
  };
  listeners.add(listener);
  return () => void listeners.delete(listener);
}

export function useEvent<T>(type: string, handler: (data: T) => void) {
  const handle = useEffectEvent(handler);
  useEffect(() => onEvent<T>(type, handle), [type]);
}

// Coalesces bursts into one refetch.
export function invalidateSoon(queryKey: QueryKey) {
  const id = JSON.stringify(queryKey);
  if (pending.has(id)) return;
  pending.set(
    id,
    window.setTimeout(() => {
      pending.delete(id);
      void queryClient.invalidateQueries({ queryKey });
    }, refetchDebounce),
  );
}

export function useConnection() {
  return useSyncExternalStore(
    (notify) => {
      watchers.add(notify);
      return () => void watchers.delete(notify);
    },
    () => status,
  );
}

// Events are hints; reconnects refetch all.
export function connectRealtime() {
  wanted = true;
  if (socket) return;
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const opened = new WebSocket(`${protocol}//${window.location.host}/api/ws`);
  socket = opened;
  setStatus("connecting");
  opened.addEventListener("open", () => {
    if (connectedBefore) void queryClient.invalidateQueries();
    connectedBefore = true;
    retryDelay = 1_000;
    setStatus("open");
  });
  opened.addEventListener("message", (event: MessageEvent<string>) => {
    const message = JSON.parse(event.data) as Message;
    listeners.forEach((listener) => listener(message));
  });
  opened.addEventListener("close", () => {
    socket = null;
    setStatus("closed");
    if (!wanted) return;
    retryTimer = window.setTimeout(connectRealtime, retryDelay);
    retryDelay = Math.min(retryDelay * 2, maxRetryDelay);
  });
}

export function disconnectRealtime() {
  wanted = false;
  window.clearTimeout(retryTimer);
  socket?.close();
}

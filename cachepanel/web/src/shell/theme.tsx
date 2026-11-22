import { createContext, useContext, useLayoutEffect, useMemo, useState, type ReactNode } from "react";

export type ColorMode = "light" | "dark";

const storageKey = "nixly-panel-theme";

type ThemeState = { mode: ColorMode; setMode: (mode: ColorMode) => void };

const ThemeContext = createContext<ThemeState | null>(null);

function storedMode(): ColorMode {
  try {
    return localStorage.getItem(storageKey) === "light" ? "light" : "dark";
  } catch {
    return "dark";
  }
}

function apply(mode: ColorMode) {
  document.documentElement.classList.toggle("dark", mode === "dark");
  document.documentElement.style.colorScheme = mode;
}

// Applied before React renders.
const initialMode = storedMode();
apply(initialMode);

function remember(mode: ColorMode) {
  try {
    localStorage.setItem(storageKey, mode);
  } catch {
    // Storage blocked; mode still applies.
  }
  return mode;
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [mode, setModeState] = useState(initialMode);
  useLayoutEffect(() => apply(mode), [mode]);

  const value = useMemo(() => ({ mode, setMode: (next: ColorMode) => setModeState(remember(next)) }), [mode]);
  return <ThemeContext value={value}>{children}</ThemeContext>;
}

export function useTheme() {
  const context = useContext(ThemeContext);
  if (!context) throw new Error("useTheme outside ThemeProvider");
  return context;
}

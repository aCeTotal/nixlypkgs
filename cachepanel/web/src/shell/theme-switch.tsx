import { Moon, Sun } from "lucide-react";
import { Switch } from "@/ui/switch";
import { useTheme } from "./theme";

export function ThemeSwitch() {
  const { mode, setMode } = useTheme();
  return (
    <div className="flex items-center gap-1.5 rounded-full border bg-card px-2.5 py-1 text-muted-foreground">
      <Sun className="size-4.5" aria-hidden />
      <Switch
        aria-label="Mørkt tema"
        checked={mode === "dark"}
        onCheckedChange={(dark) => setMode(dark ? "dark" : "light")}
      />
      <Moon className="size-4.5" aria-hidden />
    </div>
  );
}

import { useNavigate } from "@tanstack/react-router";
import { KeyRound, LogOut, UserRound } from "lucide-react";
import { useState } from "react";
import { PasswordDialog } from "@/auth/password-dialog";
import { logout, useUser } from "@/auth/session";
import { Button } from "@/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/ui/dropdown-menu";

export function UserMenu() {
  const user = useUser();
  const navigate = useNavigate();
  const [changingPassword, setChangingPassword] = useState(false);
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon" className="rounded-full" aria-label={`Brukermeny for ${user.username}`}>
            <span className="grid size-8 place-items-center rounded-full bg-gradient-to-br from-primary/20 to-chart-5/25 text-primary">
              <UserRound className="size-4" />
            </span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-60">
          <DropdownMenuLabel className="font-normal">
            <div className="font-medium">{user.username}</div>
            <div className="text-xs text-muted-foreground">Administrator</div>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => setChangingPassword(true)}>
            <KeyRound />
            Bytt passord
          </DropdownMenuItem>
          <DropdownMenuItem
            onSelect={async () => {
              await logout();
              await navigate({ to: "/login" });
            }}
          >
            <LogOut />
            Logg ut
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <PasswordDialog open={changingPassword} onOpenChange={setChangingPassword} />
    </>
  );
}

import { useMutation } from "@tanstack/react-query";
import { getRouteApi, useNavigate } from "@tanstack/react-router";
import { Boxes, CircleAlert, Layers, ShieldCheck, Wand2 } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Alert, AlertDescription } from "@/ui/alert";
import { Button } from "@/ui/button";
import { Field, FieldGroup, FieldLabel } from "@/ui/field";
import { Input } from "@/ui/input";
import { Spinner } from "@/ui/spinner";
import { login } from "./session";

const route = getRouteApi("/login");

const highlights = [
  { icon: Boxes, text: "Binary cache with the three newest versions of every derivation" },
  { icon: Layers, text: "Profiles decide modules, packages and revision" },
  { icon: ShieldCheck, text: "Everything is tested on reference machines, then approved" },
  { icon: Wand2, text: "New derivations from source, link or PKGBUILD – no code" },
];

export function LoginPage() {
  const { redirect } = route.useSearch();
  const navigate = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const signIn = useMutation({
    mutationFn: () => login(username, password),
    onSuccess: () => navigate({ href: redirect ?? "/", replace: true }),
    onError: () => setPassword(""),
  });
  const submit = (event: FormEvent) => {
    event.preventDefault();
    signIn.mutate();
  };
  return (
    <div className="grid min-h-svh lg:grid-cols-[1.1fr_1fr]">
      <aside className="relative hidden overflow-hidden bg-[oklch(0.19_0.05_250)] p-12 text-white lg:flex lg:flex-col">
        <div className="pointer-events-none absolute -top-32 -left-32 size-[32rem] bg-[radial-gradient(closest-side,oklch(0.6_0.18_240/0.45),transparent)]" />
        <div className="pointer-events-none absolute -right-24 bottom-0 size-[28rem] bg-[radial-gradient(closest-side,oklch(0.6_0.2_290/0.35),transparent)]" />
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(oklch(1_0_0/0.07)_1px,transparent_1px)] [background-size:22px_22px]" />
        <div className="relative flex items-center gap-3">
          <img src="/favicon.svg" alt="" className="size-10 rounded-xl" />
          <span className="text-lg font-semibold tracking-tight">Nixly Panel</span>
        </div>
        <div className="relative mt-auto max-w-md space-y-8">
          <h1 className="text-4xl leading-tight font-semibold tracking-tight">The whole NixlyOS fleet, in one place.</h1>
          <ul className="space-y-4">
            {highlights.map(({ icon: Icon, text }) => (
              <li key={text} className="flex items-center gap-3 text-white/85">
                <span className="grid size-9 shrink-0 place-items-center rounded-lg bg-white/10 ring-1 ring-white/15">
                  <Icon className="size-4.5" />
                </span>
                {text}
              </li>
            ))}
          </ul>
        </div>
      </aside>
      <main className="flex items-center justify-center p-6 sm:p-12">
        <form onSubmit={submit} className="w-full max-w-sm space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500">
          <div className="space-y-2">
            <h2 className="text-2xl font-semibold tracking-tight">Sign in</h2>
            <p className="text-sm text-muted-foreground">For NixlyOS administrators only.</p>
          </div>
          {signIn.error && (
            <Alert variant="destructive" className="animate-in fade-in">
              <CircleAlert />
              <AlertDescription>{signIn.error.message}</AlertDescription>
            </Alert>
          )}
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="username">Username</FieldLabel>
              <Input id="username" autoComplete="username" required value={username} onChange={(event) => setUsername(event.target.value)} />
            </Field>
            <Field>
              <FieldLabel htmlFor="password">Password</FieldLabel>
              <Input
                id="password"
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </Field>
          </FieldGroup>
          <Button type="submit" size="lg" className="w-full" disabled={signIn.isPending}>
            {signIn.isPending && <Spinner />}
            Sign in
          </Button>
        </form>
      </main>
    </div>
  );
}

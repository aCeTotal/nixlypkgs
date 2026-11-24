{ lib
, writeShellApplication
, writeText
, process-compose
, postgresql
, xdg-utils
, curl
, callPackage
, cachepanel
}:

let
  port = 8686;
  postgresPort = 54329;
  appUrl = "http://localhost:${toString port}";
  demoRepo = callPackage ./demo-repo.nix { };
  adminHash = builtins.replaceStrings [ "$" ] [ "\\$" ] (import ./default-admin-hash.nix);
  postgresArgs = "--host=127.0.0.1 --port=${toString postgresPort} --username=cachepanel";
  healthy = command: { exec.command = command; initial_delay_seconds = 1; period_seconds = 1; failure_threshold = 120; };
  after = conditions: lib.mapAttrs (_: condition: { inherit condition; }) conditions;

  composeConfig = writeText "process-compose.json" (builtins.toJSON {
    version = "0.5";
    log_location = "/dev/null";
    processes = {
      postgres = {
        command = ''
          [ -s "$STATE/postgres/PG_VERSION" ] || initdb --pgdata="$STATE/postgres" --username=cachepanel --auth=trust --no-locale --encoding=UTF8
          exec postgres -D "$STATE/postgres" -k "$STATE" -h 127.0.0.1 -p ${toString postgresPort}
        '';
        readiness_probe = healthy "pg_isready ${postgresArgs}";
      };
      setup = {
        command = ''
          psql ${postgresArgs} --dbname=postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'cachepanel'" | grep -q 1 || createdb ${postgresArgs} cachepanel
          cachepanel-demo-repo "$STATE/demo"
        '';
        depends_on = after { postgres = "process_healthy"; };
        availability.restart = "no";
      };
      panel = {
        command = "exec cachepanel serve";
        depends_on = after { setup = "process_completed_successfully"; };
        readiness_probe = healthy "curl -fsS ${appUrl}/api/health";
      };
      open-browser = {
        command = "xdg-open ${appUrl}";
        depends_on = after { panel = "process_healthy"; };
        availability.restart = "no";
      };
    };
  });
in
writeShellApplication {
  name = "cachepanel-stack";
  runtimeInputs = [ process-compose postgresql xdg-utils curl cachepanel demoRepo ];
  text = ''
    export STATE="''${CACHEPANEL_DEV_STATE:-''${XDG_STATE_HOME:-$HOME/.local/state}/cachepanel}"
    mkdir -p "$STATE"
    export CACHEPANEL_STATE_DIR="$STATE/panel"
    export CACHEPANEL_DATABASE_URL="postgres://cachepanel@127.0.0.1:${toString postgresPort}/cachepanel?sslmode=disable"
    export CACHEPANEL_HTTP_ADDR="127.0.0.1:${toString port}"
    export CACHEPANEL_SOURCE_SEED="''${CACHEPANEL_SOURCE_SEED:-file://$STATE/demo}"
    export CACHEPANEL_ADMIN_USER=nixlyos
    export CACHEPANEL_ADMIN_PASSWORD_HASH="${adminHash}"
    echo "Nixly Panel: ${appUrl}  ·  nixlyos / nixos  ·  seed: $CACHEPANEL_SOURCE_SEED  ·  data: $STATE"
    exec process-compose up --config ${composeConfig} --use-uds --unix-socket "$STATE/process-compose.sock" "$@"
  '';
  meta.mainProgram = "cachepanel-stack";
}

{ pkgs, ... }:

# Knowing a CVE landed in the running closure is the whole point of fase 5:
# vulnix walks /run/current-system against the NVD feed and the user hears
# about it once per new finding, not once per run.
let
  stateDir = "\${XDG_STATE_HOME:-$HOME/.local/state}/nixlyos";

  scan = pkgs.writeShellApplication {
    name = "nixly-cve-scan";
    runtimeInputs = with pkgs; [ vulnix jq libnotify coreutils ];
    text = ''
      state=${stateDir}
      mkdir -p "$state"
      rc=0
      vulnix --system --json > "$state/cve.json.new" 2> "$state/cve.err" || rc=$?
      # 2 = vulnerable packages found, anything else is a real failure.
      if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then
        exit "$rc"
      fi
      mv "$state/cve.json.new" "$state/cve.json"

      # Only packages that were not already affected last run: the closure
      # carries a long-lived tail of matches, and repeating it daily is noise.
      touch "$state/cve.names"
      jq -r '.[].name' "$state/cve.json" | sort > "$state/cve.names.new"
      new=$(comm -13 "$state/cve.names" "$state/cve.names.new")
      mv "$state/cve.names.new" "$state/cve.names"
      [ -n "$new" ] || exit 0

      n=$(printf '%s\n' "$new" | wc -l)
      first=$(printf '%s\n' "$new" | head -3 | paste -sd', ' -)
      notify-send -a NixlyOS -u critical \
        "$n nye pakker med kjente CVE-er" \
        "$first — kjør nixly-cve for hele listen, så update." || true
    '';
  };

  report = pkgs.writeShellApplication {
    name = "nixly-cve";
    runtimeInputs = with pkgs; [ jq coreutils ];
    text = ''
      state=${stateDir}
      if [ ! -s "$state/cve.json" ]; then
        echo "ingen skann ennå — kjør: systemctl --user start nixly-cve"
        exit 0
      fi
      jq -r '.[] | "\(.name)  \(.affected_by | join(" "))"' "$state/cve.json"
      echo
      echo "skannet: $(date -r "$state/cve.json" '+%F %T')"
    '';
  };
in
{
  home.packages = [ scan report ];

  systemd.user.services.nixly-cve = {
    Unit.Description = "CVE-skann av den kjørende systemlukningen";
    Service = {
      Type = "oneshot";
      ExecStart = "${scan}/bin/nixly-cve-scan";
    };
  };

  systemd.user.timers.nixly-cve = {
    Unit.Description = "Daglig CVE-skann";
    Timer = {
      OnCalendar = "daily";
      RandomizedDelaySec = "2h";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}

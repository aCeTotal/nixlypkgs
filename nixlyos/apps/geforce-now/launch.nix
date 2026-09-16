# The only supported way to start GFN: a transient scope inside gfn.slice
# (so the cgroup path the DSCP rule matches exists and the weights apply),
# wrapped by gfn-focus for the privileged tuning. htpc/session.nix calls
# this; on a desktop, launch `nixly-gfn` instead of the flatpak entry.
{ pkgs, ... }:

let
  gfn = pkgs.writeShellScriptBin "nixly-gfn" ''
    set -u
    SYSTEMCTL=${pkgs.systemd}/bin/systemctl
    RUN=${pkgs.systemd}/bin/systemd-run
    APP="${pkgs.flatpak}/bin/flatpak run com.nvidia.geforcenow --password-store=basic"

    "$SYSTEMCTL" start --no-block gfn-focus.service 2>/dev/null || true
    # --no-block: the guide menu must not wait for the restore pass.
    trap '"$SYSTEMCTL" stop --no-block gfn-focus.service 2>/dev/null || true' EXIT

    # No user bus (bare tty, broken session): stream beats tuning.
    if "$RUN" --user --scope --quiet --slice=gfn.slice -- true 2>/dev/null; then
      "$RUN" --user --scope --quiet --slice=gfn.slice -- $APP "$@" &
    else
      $APP "$@" &
    fi
    pid=$!
    trap 'kill -TERM $pid 2>/dev/null' TERM INT
    wait $pid
  '';

  # Icon resolves from the flatpak's exported hicolor theme.
  desktopItem = pkgs.makeDesktopItem {
    name = "com.nvidia.geforcenow";
    desktopName = "NVIDIA GeForce NOW";
    genericName = "NVIDIA GeForce NOW";
    exec = "${gfn}/bin/nixly-gfn";
    icon = "com.nvidia.geforcenow";
    categories = [ "Network" "Game" ];
  };
in
{
  environment.systemPackages = [ gfn ];

  # XDG_DATA_HOME outranks flatpak's exports dir, so the same desktop ID
  # replaces NVIDIA's entry instead of adding a second one next to it.
  home-manager.sharedModules = [
    {
      xdg.dataFile."applications/com.nvidia.geforcenow.desktop".source =
        "${desktopItem}/share/applications/com.nvidia.geforcenow.desktop";
    }
  ];
}

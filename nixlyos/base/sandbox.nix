{ pkgs, ... }:

# A browser tab is the one place untrusted code runs every day. Firejail's
# stock profiles keep it out of the rest of $HOME, so a drive-by exploit
# cannot walk the home directory or encrypt it.
#
# Steam and wine stay unjailed on purpose: Proton runs games inside its own
# bwrap namespace, which firejail refuses to nest, and firejail's seccomp
# helpers are already disabled here ("dumpable process"), so the jail would
# break gaming for filesystem confinement alone.
let
  # Stock profiles leave the session bus wide open (dbus-user none is
  # commented out), so a jailed process reaches org.freedesktop.systemd1 and
  # StartTransientUnit spawns a service outside the jail. Filter mode allows
  # only the buses a browser needs and drops systemd1, closing that escape.
  dbusFilter = [
    "--dbus-user=filter"
    "--dbus-user.talk=org.freedesktop.Notifications"
    "--dbus-user.talk=org.freedesktop.secrets"
    "--dbus-user.talk='org.freedesktop.portal.*'"
    "--dbus-user.talk=org.freedesktop.ScreenSaver"
    "--dbus-user.talk=ca.desrt.dconf"
    "--dbus-user.own='org.mpris.MediaPlayer2.*'"
  ];
  dbusArgs = builtins.concatStringsSep " \\\n          " dbusFilter;

  jail = final: { pkg, bin, profile }:
    final.symlinkJoin {
      name = "${bin}-jailed";
      paths = [ pkg ];
      inherit (pkg) meta;
      postBuild = ''
        rm -f $out/bin/${bin}
        cat > $out/bin/${bin} <<EOF
        #!${final.runtimeShell} -e
        exec /run/wrappers/bin/firejail \
          --profile=${final.firejail}/etc/firejail/${profile}.profile \
          ${dbusArgs} \
          -- ${pkg}/bin/${bin} "\$@"
        EOF
        chmod 0755 $out/bin/${bin}

        # Launchers hardcode the unwrapped store path.
        for d in $out/share/applications/*.desktop; do
          [ -e "$d" ] || continue
          real=$(readlink -f "$d")
          rm "$d"
          substitute "$real" "$d" --replace-quiet "${pkg}/bin/${bin}" "$out/bin/${bin}"
        done
      '';
    };
in
{
  # firejail's dbus filter spawns xdg-dbus-proxy from PATH.
  environment.systemPackages = [ pkgs.xdg-dbus-proxy ];

  nixpkgs.overlays = [
    (final: prev: {
      google-chrome = jail final {
        pkg = prev.google-chrome;
        bin = "google-chrome-stable";
        profile = "google-chrome";
      };
      brave = jail final {
        pkg = prev.brave;
        bin = "brave";
        profile = "brave-browser";
      };
    })
  ];
}

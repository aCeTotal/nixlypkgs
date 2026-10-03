{ pkgs, ... }:

# Steam stays unjailed: Proton needs bwrap.
let
  # Blocks systemd1 jail escape.
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

  jail = final: { pkg, bin, profile, extraArgs ? [ ] }:
    final.symlinkJoin {
      name = "${bin}-jailed";
      paths = [ pkg ];
      inherit (pkg) meta;
      postBuild = ''
        rm -f $out/bin/${bin}
        cat > $out/bin/${bin} <<'EOF'
        #!${final.runtimeShell} -e
        exec /run/wrappers/bin/firejail \
          ${builtins.concatStringsSep " " extraArgs} \
          --profile=${final.firejail}/etc/firejail/${profile}.profile \
          ${dbusArgs} \
          -- ${pkg}/bin/${bin} "$@"
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
      brave = jail final {
        pkg = prev.brave;
        bin = "brave";
        profile = "brave-browser";
        # Files arrive only through jaild.
        extraArgs = [
          "'--ignore=whitelist \${DOWNLOADS}'"
          "'--ignore=whitelist \${HOME}/.gnupg'"
          "--whitelist=~/${import ./downloads/inbox-dir.nix}"
          "--private-tmp"
        ];
      };
    })
  ];
}

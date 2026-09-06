{ pkgs, ... }:

# Autologin means PAM never sees a password, so pam_gnome_keyring can
# never unlock an encrypted login keyring — that is exactly the
# "Authentication required: the login keyring did not get unlocked"
# prompt.  The only zero-prompt setup under autologin is a BLANK
# keyring: gnome-keyring auto-unlocks blank keyrings (stored in its
# plaintext format; secrets are readable with file access — the
# accepted trade for never being asked for a password).
#
# The sanitize service runs at every login: it parks any encrypted
# keyring (binary "GnomeKeyring" magic) that would trigger the prompt,
# and lays down a blank login keyring so apps never ask to create one
# either.  Parked files are kept as *.locked-<timestamp>.
let
  sanitize = pkgs.writeShellScript "nixly-keyring-sanitize" ''
    set -u
    K="$HOME/.local/share/keyrings"
    ${pkgs.coreutils}/bin/mkdir -p "$K"
    ${pkgs.coreutils}/bin/chmod 700 "$K"
    for f in "$K"/*.keyring; do
      [ -f "$f" ] || continue
      if ${pkgs.coreutils}/bin/head -c12 "$f" \
          | ${pkgs.gnugrep}/bin/grep -q "GnomeKeyring"; then
        ${pkgs.coreutils}/bin/mv "$f" \
          "$f.locked-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
      fi
    done
    if [ ! -f "$K/login.keyring" ]; then
      ${pkgs.coreutils}/bin/cat > "$K/login.keyring" <<'EOF'
[keyring]
display-name=Login
ctime=0
mtime=0
lock-on-idle=false
lock-after=false
EOF
      ${pkgs.coreutils}/bin/chmod 600 "$K/login.keyring"
    fi
  '';
in
{
  systemd.user.services.nixly-keyring-sanitize = {
    description = "Blank login keyring so autologin never prompts";
    wantedBy = [ "default.target" ];
    before = [ "gnome-keyring-daemon.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${sanitize}";
    };
  };
}

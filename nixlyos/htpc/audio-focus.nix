# HTPC per-workspace audio: only the app on the ACTIVE workspace may
# play. nixlytile spawns `htpc-audio-focus <idx>` on every workspace
# switch (htpc_ws_refresh_fx in client.c); the script mutes every
# PipeWire output stream that belongs to another workspace's app and
# unmutes the active one. Streams that appear later (a game starting,
# RetroArch loading content) are caught by the sink-input watcher below,
# which re-applies the stored index.
#
# Workspace map (0-based, same as the compositor's active_ws->idx):
#   0 Steam (+ every game / unknown stream), 1 RetroArch,
#   2 GeForce NOW, 3 nixlymedia (mpv).
{ pkgs, lib, config, nixlyUser, ... }:

let
  audioFocus = pkgs.writeShellScriptBin "htpc-audio-focus" ''
    set -u
    RUN="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    STATE="$RUN/htpc-active-ws"

    if [ "$#" -ge 1 ]; then
      idx="$1"
      printf '%s\n' "$idx" > "$STATE"
    else
      idx="$(${pkgs.coreutils}/bin/cat "$STATE" 2>/dev/null || echo 0)"
    fi

    ${pkgs.pipewire}/bin/pw-dump 2>/dev/null | ${pkgs.jq}/bin/jq -r '
      .[] | select(.info.props["media.class"] == "Stream/Output/Audio")
      | [ .id,
          (.info.props["application.process.binary"] // ""),
          (.info.props["application.name"] // ""),
          (.info.props["node.name"] // "") ]
      | @tsv
    ' | while IFS="$(printf '\t')" read -r id bin app node; do
      s="$(printf '%s %s %s' "$bin" "$app" "$node" \
        | ${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]')"
      case "$s" in
        *retroarch*)         ws=1 ;;
        *geforce*)           ws=2 ;;
        *nixlymedia*|*mpv*)  ws=3 ;;
        *)                   ws=0 ;;  # steam, games, anything unknown
      esac
      if [ "$ws" = "$idx" ]; then mute=0; else mute=1; fi
      ${pkgs.wireplumber}/bin/wpctl set-mute "$id" "$mute" || true
    done
  '';
in
lib.mkIf (config.nixlyos.mode == "htpc") {

  environment.systemPackages = [ audioFocus ];

  # New output streams start according to the active workspace, not
  # unmuted: re-apply the stored index whenever a sink-input appears.
  home-manager.users.${nixlyUser} = {
    systemd.user.services.htpc-audio-focus-watch = {
      Unit = {
        Description = "HTPC: mute streams from inactive workspaces";
        After = [ "pipewire.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 2;
        ExecStart = pkgs.writeShellScript "htpc-audio-focus-watch" ''
          set -u
          ${audioFocus}/bin/htpc-audio-focus
          ${pkgs.pulseaudio}/bin/pactl subscribe 2>/dev/null \
          | while IFS= read -r line; do
            case "$line" in
              "Event 'new' on sink-input "*)
                sleep 0.3
                ${audioFocus}/bin/htpc-audio-focus
                ;;
            esac
          done
        '';
      };
    };
  };
}

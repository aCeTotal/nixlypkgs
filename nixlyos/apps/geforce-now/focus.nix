# Privileged half of a GFN session, started by nixly-gfn. Type=simple with
# a watch loop, not a oneshot: the unit follows the scope's own lifetime, so
# a SIGKILLed client (guide-menu switch) still restores everything through
# ExecStopPost. Every value is saved before it is changed.
{ pkgs, lib, ... }:

let
  binPath = lib.makeBinPath (with pkgs; [
    coreutils
    gnugrep
    gawk
    nftables
    systemd
    util-linux
  ]);

  # Only the app.slice/gfn.slice scope tree, whatever uid owns it.
  cgGlob = "/sys/fs/cgroup/user.slice/user-*.slice/user@*.service/app.slice/gfn.slice";

  start = pkgs.writeShellScript "gfn-focus-start" ''
    set -u
    export PATH=${binPath}

    # C-state floor, scx_lavd, GPU tuning: same as a local game.
    systemctl start nixly-gametune.service || true

    # Background downloads and vmtouch sweeps pause during the stream.
    for u in nixlyos-stage.timer nixlyos-stage.service \
             nixlyos-autoupdate.timer \
             htpc-prewarm.timer htpc-prewarm.service; do
      systemctl stop "$u" 2>/dev/null || true
    done

    # No GPU clock raise here: the stream is decode plus audio over eARC,
    # and htpc/gpu-clock.nix keeps GFN at RP1 for exactly that reason.

    # The scope appears a moment after flatpak starts.
    cg=""
    for _ in $(seq 30); do
      cg=$(ls -d ${cgGlob} 2>/dev/null | head -1)
      [ -n "$cg" ] && break
      sleep 1
    done
    [ -n "$cg" ] || exit 0

    # EF on every GFN packet regardless of port or protocol.
    rel=''${cg#/sys/fs/cgroup/}
    level=$(echo "$rel" | awk -F/ '{print NF}')
    nft add table inet gfn-live
    nft add chain inet gfn-live out '{ type route hook output priority mangle; policy accept; }'
    nft add rule inet gfn-live out socket cgroupv2 level "$level" \"$rel\" ip dscp set ef
    nft add rule inet gfn-live out socket cgroupv2 level "$level" \"$rel\" ip6 dscp set ef

    # The pids live in the nested scope, not in the slice itself.
    procs() { cat "$cg"/cgroup.procs "$cg"/*/cgroup.procs 2>/dev/null; }

    # Follow the client: empty cgroup = it is gone, ExecStopPost restores.
    applied=""
    empty=0
    while :; do
      list=$(procs)
      if [ -z "$list" ]; then
        empty=$(( empty + 1 ))
        [ "$empty" -ge 3 ] && break
      else
        empty=0
        for pid in $list; do
          case " $applied " in *" $pid "*) continue ;; esac
          echo -900 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
          ionice -c 1 -n 0 -p "$pid" 2>/dev/null || true
          applied="$applied $pid"
        done
      fi
      sleep 2
    done
  '';

  stop = pkgs.writeShellScript "gfn-focus-stop" ''
    set -u
    export PATH=${binPath}

    nft delete table inet gfn-live 2>/dev/null || true

    for u in nixlyos-stage.timer nixlyos-autoupdate.timer htpc-prewarm.timer; do
      systemctl start "$u" 2>/dev/null || true
    done

    systemctl stop nixly-gametune.service || true
  '';
in
{
  systemd.services.gfn-focus = {
    description = "Low-latency tuning while GeForce NOW streams";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${start}";
      ExecStopPost = "${stop}";
      Restart = "no";
      RuntimeDirectory = "gfn-focus";
      RuntimeDirectoryPreserve = "yes";
    };
  };

  # nixly-gfn runs as the session user.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.isInGroup("gamemode")) {
        var unit = action.lookup("unit");
        if (unit == "gfn-focus.service") {
          return polkit.Result.YES;
        }
      }
    });
  '';
}

{ pkgs, ... }:

{
  # LAN ssh stays open until tailscale logs in, then closes; the gate adds and
  # removes a runtime firewall rule based on tailscale's BackendState.
  # Failsafe: logging tailscale out reopens LAN ssh within about ten seconds.
  systemd.services.ssh-tailscale-gate = {
    description = "Open LAN ssh until tailscale is logged in";
    wantedBy = [ "multi-user.target" ];
    after = [ "firewall.service" "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    path = [ pkgs.nftables pkgs.tailscale pkgs.jq pkgs.gawk pkgs.gnugrep ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
      # Root poll loop; idle priority so its 10 s bursts never preempt a game.
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
    script = ''
      while true; do
        state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"' || true)
        rules=$(nft -a list chain inet nixos-fw input-allow 2>/dev/null || true)
        handles=$(printf '%s\n' "$rules" | awk '/tcp dport 22 accept/ {print $NF}')
        if [ "$state" = "Running" ]; then
          for h in $handles; do
            nft delete rule inet nixos-fw input-allow handle "$h" 2>/dev/null || true
          done
        else
          if [ -z "$handles" ]; then
            nft add rule inet nixos-fw input-allow tcp dport 22 accept 2>/dev/null || true
          fi
        fi
        sleep 10
      done
    '';
  };
}

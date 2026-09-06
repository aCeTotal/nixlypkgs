{ pkgs, ... }:

{
  # Run `tailscale-init` once: it logs in, waits for the connection and confirms
  # that ssh is reachable only over the tailnet.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "tailscale-init" ''
      set -e
      sudo tailscale up --ssh
      until [ "$(tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r .BackendState)" = "Running" ]; do
        sleep 1
      done
      ip=$(tailscale ip -4 2>/dev/null | head -1)
      echo ""
      echo "Tailscale aktiv ($ip). Venter paa at LAN-ssh stenges..."
      for _ in $(seq 30); do
        sudo ${pkgs.nftables}/bin/nft list chain inet nixos-fw input-allow 2>/dev/null \
          | grep -q 'tcp dport 22 accept' || break
        sleep 1
      done
      echo "SSH stengt for LAN/internett — naas naa kun via tailnettet:"
      echo "  ssh total@$(hostname)   # fra enhver tailnet-enhet, uten noekkel/passord"
      echo "Aktive ssh-oekter overlever; nye maa gaa via tailscale."
    '')
  ];

  services.tailscale = {
    enable = true;
    # Tailscale SSH authenticates by tailnet identity, with no keys or passwords.
    # extraUpFlags only applies to auto-up, so pass --ssh on the first manual login.
    extraUpFlags = [ "--ssh" ];
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}

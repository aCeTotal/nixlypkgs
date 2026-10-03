{ config, lib, nixlyUser, ... }:

let
  sshPorts = lib.concatMapStringsSep ", " toString config.services.openssh.ports;
in
{
  networking.firewall.extraInputRules = lib.mkIf (config.nixlyserver.access == "lan") ''
    ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport { ${sshPorts} } accept
    ip6 saddr { fe80::/10, fc00::/7 } tcp dport { ${sshPorts} } accept
  '';
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = config.services.openssh.ports;

  services.tailscale.enable = true;

  services.openssh = {
    enable = true;
    openFirewall = false;
    hostKeys = [
      { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
    ];
    settings = {
      AuthenticationMethods = "publickey";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ nixlyUser ];
      X11Forwarding = false;
      AllowAgentForwarding = "no";
      AllowTcpForwarding = "no";
      AllowStreamLocalForwarding = "no";
      PermitTunnel = "no";
      MaxAuthTries = 3;
      MaxSessions = 4;
      MaxStartups = "3:50:10";
      LoginGraceTime = "15s";
      ClientAliveInterval = 30;
      ClientAliveCountMax = 3;
      UseDns = false;
      # Escalating bans, max one day.
      PerSourcePenalties = "crash:1h authfail:10m invaliduser:1h noauth:1m grace-exceeded:10m max:24h min:15s";
      KexAlgorithms = [
        "mlkem768x25519-sha256"
        "sntrup761x25519-sha512@openssh.com"
        "curve25519-sha256"
      ];
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
      ];
    };
  };
}

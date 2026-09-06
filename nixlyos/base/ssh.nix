{ lib, ... }:

{
  services.openssh = {
    enable = true;
    # SSH over tailscale only; port 22 is not opened to the LAN or internet.
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      X11Forwarding = false;
      AllowTcpForwarding = "yes";
      AllowAgentForwarding = "yes";
      UseDns = false;
      ClientAliveInterval = 30;
      ClientAliveCountMax = 3;
      MaxAuthTries = 3;
      LoginGraceTime = "20s";
      Compression = "no";
      # Per-option types as the OpenSSH module expects them.
      KexAlgorithms = [
        "sntrup761x25519-sha512@openssh.com"
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
      ];
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes256-ctr"
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
      ];
    };
  };

  programs.ssh = {
    startAgent = false;
    extraConfig = ''
      Host *
        ServerAliveInterval 20
        ServerAliveCountMax 3
        AddKeysToAgent yes
        ForwardAgent yes
    '';
  };
}

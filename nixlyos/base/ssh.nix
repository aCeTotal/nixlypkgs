{ lib, nixlyUser, ... }:

{
  # sshd from private ranges only.
  networking.firewall.extraInputRules = ''
    ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 22 accept
  '';

  services.openssh = {
    enable = true;
    # Not opened globally; the LAN rule above is the only way in.
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      # Key or password, LAN only.
      PasswordAuthentication = true;
      PermitEmptyPasswords = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      AllowUsers = [ nixlyUser ];
      X11Forwarding = false;
      AllowTcpForwarding = "yes";
      # A compromised remote host must not be able to use local keys.
      AllowAgentForwarding = "no";
      MaxSessions = 4;
      MaxStartups = "3:50:10";
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
        ForwardAgent no
    '';
  };
}

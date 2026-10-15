{ lib, pkgs, ... }:

let
  nfsOptions = lib.concatStringsSep "," [
    "rw"
    "vers=4.2"
    "rsize=1048576"
    "wsize=1048576"
    "nconnect=8"
    "soft"
    "timeo=5"
    "retrans=2"
    "retry=0"
    "fsc"
    "acl"
    "noatime"
    "nodiratime"
    "tcp"
    "lookupcache=all"
    "actimeo=300"
    "nocto"
  ];
in
{
  # NFS support.
  boot.supportedFilesystems = [ "nfs" ];

  # rpcbind is NFSv3 only; the mount below is v4.2.
  services.rpcbind.enable = lib.mkForce false;

  services.cachefilesd = {
    enable = true;
    # Let the cache grow further before cleanup starts.
    # brun starts cleanup, bcull is aggressive, bstop halts caching.
    extraConfig = ''
      brun 20%
      bcull 10%
      bstop 5%
      frun 20%
      fcull 10%
      fstop 5%
    '';
  };

  # Mount directories must exist at boot.
  systemd.tmpfiles.rules = [
    "d /mnt/nfs 0755 root root -"
    "d /mnt/nfs/Bigdisk1 0755 root root -"
    "d /mnt/nfs/Bigdisk2 0755 root root -"
  ];

  # Fast reachability check that fails in about a second.
  # The mount requires it, so it never blocks on a TCP SYN timeout.
  systemd.services.nfs-bigdisk1-check = {
    description = "Check NFS server 10.0.0.8 reachability";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.iputils}/bin/ping -c 1 -W 1 10.0.0.8 > /dev/null 2>&1'";
    };
    unitConfig = {
      StartLimitIntervalSec = 0;
    };
  };

  # Mount units gated on the reachability check above.
  systemd.mounts = [
    {
      what = "10.0.0.8:/bigdisk1";
      where = "/mnt/nfs/Bigdisk1";
      type = "nfs";
      mountConfig = {
        Options = nfsOptions;
        TimeoutSec = "5s";
      };
      requires = [ "nfs-bigdisk1-check.service" ];
      after = [ "nfs-bigdisk1-check.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig = {
        StartLimitIntervalSec = 0;
      };
    }
    {
      what = "10.0.0.8:/bigdisk2";
      where = "/mnt/nfs/Bigdisk2";
      type = "nfs";
      mountConfig = {
        Options = nfsOptions;
        TimeoutSec = "5s";
      };
      requires = [ "nfs-bigdisk1-check.service" ];
      after = [ "nfs-bigdisk1-check.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig = {
        StartLimitIntervalSec = 0;
      };
    }
  ];

  # Automounts trigger on access. TimeoutIdleSec=0: never tear down an idle
  # mount — an unmount drops the page cache, attribute cache and the eight
  # TCP connections, and the next access pays the whole mount latency again.
  # The automount layer is kept only so a down server never blocks boot and
  # access after an outage re-mounts lazily.
  systemd.automounts = [
    {
      where = "/mnt/nfs/Bigdisk1";
      automountConfig = {
        TimeoutIdleSec = 0;
      };
      wantedBy = [ "multi-user.target" ];
    }
    {
      where = "/mnt/nfs/Bigdisk2";
      automountConfig = {
        TimeoutIdleSec = 0;
      };
      wantedBy = [ "multi-user.target" ];
    }
  ];

  # statfs every 30 s keeps NFS warm.
  systemd.services.nfs-keepalive = {
    description = "Keep NFS mounts mounted and their connections warm";
    wantedBy = [ "multi-user.target" ];
    after = [ "remote-fs.target" ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "nfs-keepalive" ''
        while :; do
          for d in /mnt/nfs/*; do
            ${pkgs.coreutils}/bin/stat -f "$d" > /dev/null 2>&1 &
          done
          wait
          ${pkgs.coreutils}/bin/sleep 30
        done
      '';
      Restart = "always";
    };
  };
}

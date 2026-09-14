# The NFS bdi comes up with read_ahead_kb=256, a quarter of one rsize. One
# full rsize of readahead is what actually saturates the gigabit link.
# Measured on the HTPC, buffered 256 MB reads of untouched regions of a PS2
# ISO, two runs per value:
#
#   128 KB   97 MB/s
#   256 KB   97, 101 MB/s   (default)
#   1024 KB  114, 114 MB/s  <- link rate
#   4096 KB  56 MB/s
#   15360 KB 57, 58 MB/s
#
# Past one rsize it collapses: the oversized readahead runs ahead of what
# the eight connections and the fscache writeback can absorb, and the reader
# ends up waiting on requests it will not use. 1 MB, not "as big as
# possible".
#
# The mounts are kept up permanently now (base/nfs.nix), but a re-mount
# after a server outage still comes back with a fresh bdi at the kernel
# default, so this stays bound to the mount units and re-runs on every mount.
{ pkgs, ... }:

{
  systemd.services.nfs-readahead = {
    description = "Raise NFS readahead to one rsize (1 MB)";
    after = [ "mnt-nfs-Bigdisk1.mount" "mnt-nfs-Bigdisk2.mount" ];
    wantedBy = [ "mnt-nfs-Bigdisk1.mount" "mnt-nfs-Bigdisk2.mount" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nfs-readahead" ''
        set -u
        # mountinfo: id parent maj:min root mountpoint opts [tags] - fstype ...
        while read -r _ _ majmin _ _ _ rest; do
          case "$rest" in
            *" nfs "*|*" nfs4 "*) ;;
            *) continue ;;
          esac
          f=/sys/class/bdi/$majmin/read_ahead_kb
          [ -w "$f" ] && echo 1024 > "$f"
        done < /proc/self/mountinfo
        exit 0
      '';
    };
  };
}

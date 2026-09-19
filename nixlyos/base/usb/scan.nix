{ pkgs, lib, hwData, ... }:

let
  expand = pkgs.callPackage ../scanbox/expand.nix { };

  scan = pkgs.writeShellApplication {
    name = "nixly-usbscan";
    runtimeInputs = with pkgs; [
      b3sum
      clamav
      coreutils
      expand
      findutils
      gnugrep
      gnused
      systemd
      util-linux
    ];
    text = builtins.readFile ./scan.sh;
  };
in
{
  # Every removable filesystem is scanned before anything may mount it.
  # ClamAV signatures refresh hourly, plus the Sanesecurity/URLhaus/InterServer
  # feeds that carry same-day coverage for script droppers and loaders.
  services.clamav = {
    updater.enable = true;
    updater.interval = "hourly";
    updater.frequency = 24;
    fangfrisch.enable = true;
    fangfrisch.interval = "hourly";
    fangfrisch.settings = {
      interserver.enabled = "yes";
      urlhaus.enabled = "yes";
      sanesecurity.enabled = "yes";
    };
    daemon.enable = true;
    daemon.settings = {
      # Depth over speed on the content itself: archives, installers, office
      # macros and PUA all count as "everything", and clamd is threaded.
      MaxThreads = hwData.resources.buildCores;
      ScanArchive = true;
      ScanPE = true;
      ScanELF = true;
      ScanOLE2 = true;
      ScanPDF = true;
      ScanSWF = true;
      ScanHTML = true;
      ScanXMLDOCS = true;
      ScanHWP3 = true;
      AlertOLE2Macros = true;
      AlertEncrypted = true;
      AlertPartitionIntersection = true;
      DetectPUA = true;
      HeuristicAlerts = true;
      MaxRecursion = 16;
      MaxFiles = 50000;
      MaxFileSize = "256M";
      MaxScanSize = "1024M";
      # Reloading in place would double the resident signature set.
      ConcurrentDatabaseReload = false;
    };
  };

  # clamd holds the whole signature set in RAM (~1 GB). Nothing keeps it
  # resident: a scan starts it, and the scan stops it again the instant the
  # last partition finishes, so an idle desktop never carries it.
  systemd.services.clamav-daemon.wantedBy = lib.mkForce [ ];

  # Database downloads must never compete with the foreground desktop.
  systemd.services.clamav-freshclam.serviceConfig = {
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass = "idle";
    Nice = 19;
  };
  systemd.services.clamav-fangfrisch.serviceConfig = {
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass = "idle";
    Nice = 19;
  };

  systemd.services."nixly-usbscan@" = {
    description = "Scan removable filesystem %i before mount";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${scan}/bin/nixly-usbscan %i";
      RuntimeDirectory = "nixly-usbscan";
      RuntimeDirectoryPreserve = true;
      # Persistent clean-hash cache; survives reboots.
      StateDirectory = "nixly-usbscan";
      StateDirectoryMode = "0700";
      # A big stick takes as long as it takes; progress is on screen.
      TimeoutStartSec = "infinity";
    };
  };

  services.udev.extraRules = ''
    # USB partitions carrying a filesystem. Whole disks, empty partitions and
    # everything internal never reach the scanner. The scan unit pulls clamd
    # up itself, so nothing keeps it resident just because a stick is plugged.
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", TAG+="systemd", ENV{SYSTEMD_WANTS}+="nixly-usbscan@$kernel.service"
    ACTION=="remove", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", RUN+="${pkgs.coreutils}/bin/rm -f /run/nixly-usbscan/$kernel.state"
  '';
}

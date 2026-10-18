{ hwData, ... }:

{
  # Hourly signatures plus same-day feeds.
  services.clamav = {
    updater.enable = true;
    updater.interval = "hourly";
    updater.frequency = 24;
    fangfrisch.enable = true;
    fangfrisch.interval = "hourly";
    fangfrisch.settings = {
      interserver.enabled = "yes";
      urlhaus.enabled = "yes";
      urlhaus.max_size = "16MB";
      sanesecurity.enabled = "yes";
    };
    daemon.enable = true;
    daemon.settings = {
      # Depth over speed, everything.
      MaxThreads = hwData.resources.cores;
      # Unpacked members stay off tmpfs.
      TemporaryDirectory = "/var/tmp";
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
      # 2G is the engine ceiling.
      MaxFileSize = "2G";
      MaxScanSize = "4G";
      # Hitting a limit is a verdict.
      AlertExceedsMax = true;
      # In-place reload doubles memory.
      ConcurrentDatabaseReload = false;
    };
  };

  # Updates yield to the desktop.
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
}

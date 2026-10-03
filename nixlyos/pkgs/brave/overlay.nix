final: prev: {
  # Replaces wrapper's feature list.
  brave = prev.brave.override {
    commandLineArgs = builtins.concatStringsSep " " [
      # Session kill fakes crashes.
      "--hide-crash-restore-bubble"
      "--no-default-browser-check"
      # NVIDIA GMB frames crash renderer.
      "--disable-gpu-memory-buffer-video-frames"
      "--enable-features=${builtins.concatStringsSep "," [
        "AcceleratedVideoDecodeLinuxGL"
        "AcceleratedVideoDecodeLinuxZeroCopyGL"
        "AcceleratedVideoEncoder"
        "VaapiOnNvidiaGPUs"
        "VaapiIgnoreDriverChecks"
        "WaylandWindowDecorations"
      ]}"
    ];
  };
}

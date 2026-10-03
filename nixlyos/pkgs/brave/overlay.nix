final: prev: {
  # Session kill fakes crashes; NVIDIA GMB video frames crash renderer.
  brave = prev.brave.override {
    commandLineArgs = "--hide-crash-restore-bubble --no-default-browser-check --disable-gpu-memory-buffer-video-frames";
  };
}

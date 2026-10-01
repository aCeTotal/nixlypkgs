final: prev: {
  # Session kill fakes crashes; NVIDIA GMB video frames crash renderer.
  google-chrome = prev.google-chrome.override {
    commandLineArgs = "--hide-crash-restore-bubble --disable-session-crashed-bubble --no-default-browser-check --disable-gpu-memory-buffer-video-frames";
  };
}

final: prev: {
  # Chrome is hard-killed when the Wayland session ends, so it always thinks it
  # crashed; these flags suppress the "Restore pages?" bubble for good.
  google-chrome = prev.google-chrome.override {
    commandLineArgs = "--hide-crash-restore-bubble --disable-session-crashed-bubble --no-default-browser-check";
  };
}

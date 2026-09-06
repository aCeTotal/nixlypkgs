final: prev: {
  # wfica is X11-only, but detects Wayland and then passes an Xlib pointer to the
  # Wayland EGL platform, which segfaults; pretending the session is X11 avoids it.
  # EGL_PLATFORM must be set explicitly too, since .ica files open as children of
  # Chrome and would inherit its EGL_PLATFORM=wayland.
  citrix-workspace-nixly = prev.citrix-workspace-nixly.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      for prog in wfica selfservice storebrowse conncenter configmgr; do
        wrapProgram $out/bin/$prog \
          --unset WAYLAND_DISPLAY \
          --set XDG_SESSION_TYPE x11 \
          --set EGL_PLATFORM x11
      done

      # DrivePathA=$HOME exposes every dot-file, so hide them from the CDM listing;
      # module.ini is never copied to ~/.ICAClient, so the store copy is the one used.
      sed -i 's/^CDMHideHiddenFile\([[:space:]]*\)=.*/CDMHideHiddenFile\1= 1/' \
        $out/opt/citrix-icaclient/config/module.ini

      # Also disabled here, since module.ini beats the wfclient.ini setting that
      # wfica rewrites on every GUI change.
      sed -i 's/^SuperMetaToWinKeys[[:space:]]*=.*/SuperMetaToWinKeys=False/' \
        $out/opt/citrix-icaclient/config/module.ini
    '';
  });
}

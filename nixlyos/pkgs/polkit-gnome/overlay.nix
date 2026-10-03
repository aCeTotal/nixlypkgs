final: prev: {
  # Endless retries, no boilerplate text.
  polkit_gnome = prev.polkit_gnome.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./dialog.patch ];
  });
}

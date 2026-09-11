{
  # systemMode (legacy — prefer nixlyos.mode = "htpc" in ~/.local/nixlyos/local.nix):
  #   1 = desktop only (Niri session, SDDM login screen)
  #   2 = htpc only (auto-login, Steam Big Picture, htpc/ modules active)
  systemMode = 1;

  # autoLogin: true = SDDM skip login, straight into nixlytile as the primary user.
  #            false = normal SDDM login prompt.
  autoLogin = false;
}

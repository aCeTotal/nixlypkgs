{
  # systemMode:
  #   1 = desktop only (Niri session, SDDM login screen)
  #   2 = htpc only (auto-login, htpc.nix activates: retroarch + jellyfin + HM configs)
  systemMode = 1;

  # autoLogin: true = SDDM skip login, straight into nixlytile as the primary user.
  #            false = normal SDDM login prompt.
  autoLogin = false;
}

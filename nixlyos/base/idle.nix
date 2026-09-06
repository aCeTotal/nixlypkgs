{ ... }:

{
  # The screen never blanks and the machine never auto-suspends on idle; idle
  # locking is handled by the nixly-idled user service.
  #
  # Lid close = plain S3 suspend on both battery and AC. The first
  # suspend-then-hibernate lid cycle (2026-09-03 00:54, boot 609a5946) hung
  # hard in kernel resume — no "PM: suspend exit" ever logged, frozen
  # framebuffer, power-cycle required — while four plain-suspend cycles the
  # same day resumed cleanly with identical kernel params. Keep plain
  # suspend until s-t-h resume is debugged (pstore/no_console_suspend);
  # hibernate.nix (swapfile, HibernateDelaySec) stays in place for that.
  # Docked (external monitor) keeps ignoring the lid so closing the laptop
  # at a desk doesn't kill the session.
  services.logind.settings.Login = {
    IdleAction = "ignore";
    IdleActionSec = 0;
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };
}

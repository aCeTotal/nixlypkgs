# CachyOS-grunnvalg + scheduler (tilsvarer _cachy_config=yes, _cpusched=cachyos).
[
  "-e CACHY"
  "-e SCHED_BORE"
  # sched_ext: kreves av scx_lavd og resten av scx-familien.
  "-e SCHED_CLASS_EXT"
  # Støttes ikke av nixpkgs.
  "-d SECURITY_TOMOYO"
  # Skjules uansett av Kconfig under clang-LTO (rustc/clang-versjonsmatch);
  # eksplisitt av for deterministisk config.
  "-d RUST"
]

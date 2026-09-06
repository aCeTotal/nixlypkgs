{ config, ... }:

{
  # The name in /etc/os-release, /etc/lsb-release, the boot entries and nixos-version.
  # distroId stays "nixos": tools check the ID to recognise the platform, and a
  # custom one makes them fall back to generic Linux.
  system.nixos = {
    distroName = "NixlyOS";
    vendorName = "NixlyOS";

    # These fields are inert strings hardcoded to nixos.org upstream, so they are
    # pointed here instead; LOGO stays put, since the icon must exist in the theme.
    extraOSReleaseArgs = {
      CPE_NAME = "cpe:/o:nixlyos:nixlyos:${config.system.nixos.release}";
      DEFAULT_HOSTNAME = "nixlyos";
      HOME_URL = "https://github.com/aCeTotal/nixlypkgs";
      VENDOR_URL = "https://github.com/aCeTotal/nixlypkgs";
      DOCUMENTATION_URL = "https://github.com/aCeTotal/nixlypkgs";
      SUPPORT_URL = "https://github.com/aCeTotal/nixlypkgs";
      BUG_REPORT_URL = "https://github.com/aCeTotal/nixlypkgs/issues";
    };
  };
}

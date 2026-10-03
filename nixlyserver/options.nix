# Settings the panel owns.
{ lib, ... }:

let
  nato = [
    "AL" "BE" "BG" "CA" "CZ" "DE" "DK" "EE" "ES" "FI" "FR" "GB" "GR" "HR" "HU" "IS"
    "IT" "LT" "LU" "LV" "ME" "MK" "NL" "NO" "PL" "PT" "RO" "SE" "SI" "SK" "TR" "US"
  ];
in
{
  options.nixlyserver = {
    access = lib.mkOption {
      type = lib.types.enum [ "lan" "vpn" ];
      default = "lan";
      description = "Where SSH answers: LAN plus tailnet, or tailnet only.";
    };

    updates = lib.mkOption {
      type = lib.types.enum [ "auto-reboot" "auto" "manual" ];
      default = "auto-reboot";
      description = "Nightly update with reboot on kernel change, nightly update only, or never.";
    };

    allowedCountries = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Z]{2}");
      default = nato;
      description = "ISO 3166 codes whose public IPv4 space may open connections.";
    };
  };
}

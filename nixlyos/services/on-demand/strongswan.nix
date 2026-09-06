{ config, lib, ... }:

{
  systemd.services.strongswan.wantedBy = lib.mkForce [ ];
}

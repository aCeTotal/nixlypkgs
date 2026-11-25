# A profile with every module, for tools.
{ lib, ... }:

{
  nixlyos.mode = lib.mkForce "desktop";
}

# Selected catalog modules.
{ hwData, nixlySelection, ... }:

{
  imports = (import ../lib/catalog-pick.nix { inherit hwData nixlySelection; }).pick "system";
}

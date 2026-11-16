{ config, lib, ... }:

{
  # Fewer metadata writes on root.
  fileSystems."/".options = lib.mkIf (config.fileSystems."/".fsType == "ext4")
    [ "noatime" "lazytime" "commit=120" ];
}

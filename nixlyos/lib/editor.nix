# What the panel's editor completes.
{ self, lib }:
system:
let
  machine = self.lib.mkNixlySystem {
    hostName = "nixly-editor";
    username = "nixly";
    stateVersion = "25.05";
    hardwareDir = ../reference/profiles/nvidia-desktop;
    profileTree = ../reference/tree;
  };
  text = value: if builtins.isString value then value else value.text or "";
  # The first paragraph, kept short.
  summary = value: builtins.substring 0 280 (builtins.head (lib.splitString "\n\n" (text value)));
  options = builtins.filter (option: option.visible && !option.internal) (lib.optionAttrSetToDocList machine.options);
in
{
  options = map (option: {
    inherit (option) name type;
    description = summary (option.description or "");
  }) options;
  packages = builtins.attrNames (self.lib.nixlyos.pkgs system);
  lib = builtins.attrNames lib ++ map (name: "types." + name) (builtins.attrNames lib.types);
  builtins = builtins.attrNames builtins;
}

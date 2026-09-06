{ ... }:

let
  policy = builtins.toJSON {
    BackgroundModeEnabled = false;
  };
in
{
  environment.etc."opt/chrome/policies/managed/no-background.json".text = policy;
  environment.etc."chromium/policies/managed/no-background.json".text = policy;
}

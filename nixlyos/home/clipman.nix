{ pkgs, ... }:

{
  # Provide Clipman clipboard manager to the user environment
  home.packages = with pkgs; [ clipman ];
}


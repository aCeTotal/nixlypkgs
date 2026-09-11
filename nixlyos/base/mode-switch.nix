# install_htpc / install_desktop: switch the machine between the two
# configuration sets (nixlyos.mode in ~/.local/nixlyos/local.nix), and
# nixlyos-migrate: the stock migration from the old ~/.nixlyos repo to the
# nixlypkgs architecture — set-mode.sh runs it automatically when it finds
# a machine still on the old layout.
{ pkgs, lib, ... }:

let
  scripts = ../scripts;

  # migrate-to-local.sh verbatim (it fetches current nixlypkgs main itself);
  # writeScriptBin, not writeShellApplication: the script predates shellcheck
  # gating here and must ship unmodified.
  migrate = pkgs.writeScriptBin "nixlyos-migrate" ''
    #!${pkgs.runtimeShell}
    export PATH=${lib.makeBinPath (with pkgs; [
      coreutils curl gnutar gzip gnugrep gnused gawk nix nettools
    ])}:/run/wrappers/bin:/run/current-system/sw/bin:$PATH
    ${builtins.readFile (scripts + "/migrate-to-local.sh")}
  '';

  setMode = pkgs.writeShellApplication {
    name = "nixlyos-set-mode";
    runtimeInputs = with pkgs; [
      coreutils gnugrep gnused gawk nix migrate
    ];
    text = ''
      export PATH=/run/wrappers/bin:$PATH
      ${builtins.readFile (scripts + "/set-mode.sh")}
    '';
  };

  installMode = mode: pkgs.writeShellScriptBin "install_${mode}" ''
    NIXLY_MODE=${mode} exec ${setMode}/bin/nixlyos-set-mode "$@"
  '';
in
{
  environment.systemPackages = [
    migrate
    setMode
    (installMode "htpc")
    (installMode "desktop")
  ];
}

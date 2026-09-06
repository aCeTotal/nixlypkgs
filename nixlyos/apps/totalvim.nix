{ totalvimPkg, ... }:

{
  home-manager.sharedModules = [
    {
      home.packages = [ totalvimPkg ];

      # Global clangd config: use the project's compiler (nix devShell `cc` from
      # `nix develop`/direnv) as the driver, so opening any C/C++ file auto-discovers
      # every buildInput's headers. Per-project .clangd (e.g. STM32) overrides this.
      xdg.configFile."clangd/config.yaml".text = ''
        CompileFlags:
          Compiler: cc
      '';
    }
  ];
}

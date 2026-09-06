{ pkgs, ... }:

{

    home.packages = with pkgs; [
        libsecret
        git-lfs
    ];

    programs.git = {
        enable = true;
        package = pkgs.gitFull;
        signing.format = null;
        settings.user = {
            name = "aCeTotal";
            email = "lars.oksendal@gmail.com";
        };
    };

    programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings = {
          "*" = {
            Compression = true;
          };
          "github.com" = {
            IdentityFile = "~/.ssh/github";
          };
        };
    };
}

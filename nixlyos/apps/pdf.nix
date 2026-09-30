# Nixly-PDF: eneste PDF-verktøy.
{ lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "desktop") {
  home-manager.sharedModules = [
    ({ pkgs, ... }: {
      home.packages = [ pkgs.nixly_pdf ];

      xdg.mimeApps = {
        enable = true;
        defaultApplications."application/pdf" = [ "nixly-pdf.desktop" ];
        associations.removed."application/pdf" = [
          "draw.desktop"
          "google-chrome.desktop"
          "com.google.Chrome.desktop"
          "brave-browser.desktop"
          "com.brave.Browser.desktop"
        ];
      };
    })
  ];
}

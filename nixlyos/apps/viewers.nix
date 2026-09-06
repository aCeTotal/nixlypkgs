# PDF-leser (zathura) og bildeviser (swayimg) med xdg-mime-defaults,
# så xdg-open og filbehandlere åpner dem automatisk.
{ ... }:

{
  config.home-manager.sharedModules = [
    ({ pkgs, ... }: {
      home.packages = with pkgs; [
        zathura
        swayimg
      ];

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];

          # Alle formatene swayimg selv oppgir i sin .desktop-fil.
          "image/avif" = [ "swayimg.desktop" ];
          "image/bmp" = [ "swayimg.desktop" ];
          "image/gif" = [ "swayimg.desktop" ];
          "image/heif" = [ "swayimg.desktop" ];
          "image/jpeg" = [ "swayimg.desktop" ];
          "image/jpg" = [ "swayimg.desktop" ];
          "image/jxl" = [ "swayimg.desktop" ];
          "image/pbm" = [ "swayimg.desktop" ];
          "image/pjpeg" = [ "swayimg.desktop" ];
          "image/png" = [ "swayimg.desktop" ];
          "image/svg+xml" = [ "swayimg.desktop" ];
          "image/tiff" = [ "swayimg.desktop" ];
          "image/webp" = [ "swayimg.desktop" ];
          "image/x-bmp" = [ "swayimg.desktop" ];
          "image/x-exr" = [ "swayimg.desktop" ];
          "image/x-png" = [ "swayimg.desktop" ];
          "image/x-portable-anymap" = [ "swayimg.desktop" ];
          "image/x-portable-bitmap" = [ "swayimg.desktop" ];
          "image/x-portable-graymap" = [ "swayimg.desktop" ];
          "image/x-portable-pixmap" = [ "swayimg.desktop" ];
          "image/x-targa" = [ "swayimg.desktop" ];
          "image/x-tga" = [ "swayimg.desktop" ];
        };
      };
    })
  ];
}

{ pkgs, ... }:

{
  # Nautilus (GNOME Files) som filbehandler. gvfs/udisks2 er aktivert
  # system-wide (system_services.nix) og gir trash, mounts, smb:// og mtp.
  home.packages = with pkgs; [
    nautilus
    file-roller        # arkiv-GUI; "Extract here" i Nautilus
    ffmpegthumbnailer  # video-thumbnails
  ];

  # Nautilus er libadwaita og ignorerer GTK-temaet i gtk.nix; mørkt tema
  # styres av color-scheme-innstillingen.
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  xdg.mimeApps.defaultApplications."inode/directory" =
    [ "org.gnome.Nautilus.desktop" ];

  # Hardening mot heng når en SMB-server er nede: gvfs-smb bruker også
  # libsmbclient og leser denne. Connect-timeout er i millisekunder.
  home.file.".smb/smb.conf".text = ''
    [global]
        client min protocol = SMB2
        client max protocol = SMB3
        client ipc max protocol = SMB3
        # Skip WINS and lmhosts, which hang without a WINS server.
        name resolve order = host bcast
        # A failed connect gives up after 3 s instead of 30.
        client connection timeout = 3000
        socket options = TCP_NODELAY IPTOS_LOWDELAY
  '';
}

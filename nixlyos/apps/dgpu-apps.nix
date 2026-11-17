# Hybrid laptops run every video, compute and game app on the dGPU.
{ lib, hwData, ... }:

let
  chromiumNode = "--render-node-override=";

  # Installed apps: binaries to wrap and the flag taking the dGPU render node.
  joined = {
    brave = { bins = [ "brave" ]; nodeArg = chromiumNode; };
    google-chrome = { bins = [ "google-chrome-stable" "google-chrome" ]; nodeArg = chromiumNode; };
    vlc = { bins = [ "vlc" "cvlc" "nvlc" "qvlc" "rvlc" "svlc" ]; };
    nixlymedia = { bins = [ "nixlymedia" ]; };
    lutris = { bins = [ "lutris" ]; };
    Blender_bin_lts = { bins = [ "blender" ]; };
    gaea = { bins = [ "gaea" ]; };
  };

  wrapBins = final: { bins, nodeArg ? null }: lib.concatMapStrings (bin: ''
    mv "$out/bin/${bin}" "$out/bin/.${bin}-dgpu"
    makeBinaryWrapper ${final.nixly-dgpu}/bin/nixly-dgpu "$out/bin/${bin}" ${
      lib.optionalString (nodeArg != null) "--add-flag --node-arg --add-flag ${nodeArg}"
    } --add-flag "$out/bin/.${bin}-dgpu"
  '') bins;

  dgpuJoin = final: pkg: spec: final.symlinkJoin {
    inherit (pkg) name meta;
    paths = [ pkg ];
    nativeBuildInputs = [ final.makeBinaryWrapper ];
    postBuild = ''
      # FHS envs link the directory.
      if [ -L "$out/share/applications" ]; then
        apps=$(readlink -f "$out/share/applications")
        rm "$out/share/applications"
        mkdir "$out/share/applications"
        ln -s "$apps"/* "$out/share/applications/"
      fi
      # Launchers hardcode the unwrapped path.
      for d in $out/share/applications/*.desktop; do
        [ -e "$d" ] || continue
        real=$(readlink -f "$d")
        rm "$d"
        substitute "$real" "$d" --replace-quiet "${pkg}/bin/" "$out/bin/"
      done
    '' + wrapBins final spec;
  };

  # For packages that already are symlinkJoin wrappers.
  dgpuAppend = final: drv: spec: drv.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeBinaryWrapper ];
    buildCommand = old.buildCommand + wrapBins final spec;
  });
in
lib.mkIf hwData.dmi.isLaptop {
  # After the jail and GPU-module overlays, so this wrapper is outermost.
  nixpkgs.overlays = lib.mkAfter [
    (final: prev: lib.mapAttrs (name: dgpuJoin final prev.${name}) joined // {
      # overrideAttrs keeps mpv.override, which programs.mpv calls.
      mpv = dgpuAppend final prev.mpv { bins = [ "mpv" ]; nodeArg = "--vaapi-device="; };
      retroarch =
        let wrap = r: dgpuAppend final r { bins = [ "retroarch" ]; } // { withCores = f: wrap (r.withCores f); };
        in wrap prev.retroarch;
    })
  ];
}

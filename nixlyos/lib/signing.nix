# Panel signatures for booting.
signingFile:
{ config, lib, options, pkgs, ... }:

let
  kernel = config.boot.kernelPackages.kernel;
  bundles = if builtins.pathExists signingFile then import signingFile else { };
  signed = bundles != { };
  bootEfi = "${config.systemd.package}/lib/systemd/boot/efi/systemd-bootx64.efi";
  kernelImage = "${kernel}/${config.system.boot.loader.kernelFile}";
  esp = config.boot.loader.efi.efiSysMountPoint;

  # Attribute names carry no context.
  nameOf = path: builtins.unsafeDiscardStringContext (builtins.baseNameOf path);

  signatures = pkg: pkgs.runCommand "${pkg.name}-signatures" { } ''
    mkdir $out
    tar -xf ${pkgs.fetchurl bundles.${nameOf pkg}} -C $out
  '';

  # PKCS#7 signature, module_signature trailer, magic.
  signModules = pkg: pkgs.runCommand "${pkg.name}-signed" { } ''
    cp -a ${pkg} $out
    chmod -R u+w $out
    find $out -name '*.ko' -type f | while read -r ko; do
      sig=${signatures pkg}/$(sha256sum "$ko" | cut -d' ' -f1).module
      [ -f "$sig" ] || { echo "unsigned module: $ko" >&2; exit 1; }
      len=$(stat -c %s "$sig")
      cat "$sig" >> "$ko"
      printf '\0\0\2\0\0\0\0\0' >> "$ko"
      printf "$(printf '\\%03o\\%03o\\%03o\\%03o' $((len >> 24 & 255)) $((len >> 16 & 255)) $((len >> 8 & 255)) $((len & 255)))" >> "$ko"
      printf '~Module signature appended~\n' >> "$ko"
    done
  '';

  signEfi = pkg: file: pkgs.runCommand "${nameOf file}-signed" { nativeBuildInputs = [ pkgs.sbsigntool ]; } ''
    install -m 0644 ${file} $out
    sbattach --attach ${signatures pkg}/$(sha256sum ${file} | cut -d' ' -f1).efi $out
  '';

  signedTree = pkg: if bundles ? ${nameOf pkg} then signModules pkg else pkg;
  signedKernel = signEfi kernel kernelImage;
in
{
  # The panel collects and checks these.
  system.systemBuilderCommands = lib.mkAfter (''
    ln -s ${bootEfi} $out/systemd-boot.efi
  '' + lib.optionalString (kernel ? caCert) ''
    ln -s ${kernel.caCert} $out/nixlyos-ca.pem
  '' + lib.optionalString signed ''
    ln -sfn ${signedKernel} $out/kernel
  '');

  # systemd-boot installs bootspec's kernel.
  boot.bootspec.writer = lib.mkIf signed (lib.mkForce ''
    ${options.boot.bootspec.writer.default}
    ${lib.getExe pkgs.buildPackages.jq} --arg kernel ${signedKernel} '."org.nixos.bootspec.v1".kernel = $kernel' $out/boot.json > boot.json
    mv boot.json $out/boot.json
  '');

  system.modulesTree = lib.mkIf signed
    (lib.mkForce (map signedTree ([ (lib.getOutput "modules" kernel) ] ++ config.boot.extraModulePackages)));

  boot.loader.systemd-boot = lib.mkIf signed {
    # No init= shell at boot.
    editor = false;
    extraInstallCommands = ''
      for target in EFI/systemd/systemd-bootx64.efi EFI/BOOT/BOOTX64.EFI; do
        install -m 0644 ${signEfi config.systemd.package bootEfi} ${esp}/$target
      done
    '';
  };
}

# Nixpkgs config for the machine pkgs instance (mk-system). The flake's
# packages output imports the same file so cache entries are evaluated
# under identical gating.
{
  allowUnfree = true;

  permittedInsecurePackages = [
    "freeimage-unstable-2021-11-01"
    "electron-29.4.6"
    "dotnet-sdk-6.0.428"
    "dotnet-runtime-6.0.36"
    "dotnet-sdk-wrapped-6.0.428"
    "libxml2-2.13.8"
    "libsoup-2.74.3"
  ];

  # The old NVIDIA branches need explicit license acceptance on top of
  # allowUnfree, or eval fails on Kepler and older machines.
  nvidia.acceptLicense = true;
}

# The HTPC RetroArch bundle. One definition shared by media.nix (installs
# it) and prewarm.nix (keeps it in RAM) — same expression, same store path.
{ pkgs }:

pkgs.retroarch.withCores (cores: with cores; [
  nestopia
  snes9x
  bsnes
  genesis-plus-gx
  mupen64plus
  beetle-psx-hw
  pcsx-rearmed
  mgba
  gambatte
  beetle-saturn
  flycast
  melonds
  mame
  stella
  ppsspp
  fbneo
  # PS2 and GameCube/Wii — the ROM share has folders for both
  # (playlists in rom-playlists.nix point straight at these cores).
  pcsx2
  dolphin
])

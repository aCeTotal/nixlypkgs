# stm32cubeide

Full generic Linux release of **STM32CubeIDE** — the Eclipse IDE with the
**integrated STM32CubeMX** device configurator, GNU Arm toolchain, GDB and
ST-Link/J-Link support. CubeMX is built in (the `.ioc` editor); no separate MX
install is needed.

ST gates the download behind a login, so the installer cannot be fetched
automatically. It is provided via `requireFile`.

## Install

1. Download **"STM32CubeIDE Generic Linux Installer"** (ST login required):
   <https://www.st.com/en/development-tools/stm32cubeide.html>
2. Unzip → you get `stm32cubeide_<ver>_<build>_<date>-Lin-x86_64.sh`.
3. Rename it to match the packaged version, e.g. `stm32cubeide-2.2.0-Lin-x86_64.sh`.
4. Hash and add to the store:
   ```sh
   nix hash file stm32cubeide-2.2.0-Lin-x86_64.sh
   nix-store --add-fixed sha256 stm32cubeide-2.2.0-Lin-x86_64.sh
   ```
5. Set the hash via override (in your overlay / config):
   ```nix
   stm32cubeide.override {
     version = "2.2.0";
     sha256  = "sha256-....";   # from step 4
   }
   ```

Unfree license — set `nixpkgs.config.allowUnfree = true;` (or
`allowUnfreePredicate` for just `stm32cubeide`).

## Wayland

Runs natively on Wayland by default; falls back to XWayland automatically.
The launcher sets:

- `GDK_BACKEND=wayland,x11` — native Wayland, XWayland fallback
- `SWT_GTK3=1` — force GTK3 SWT backend
- `_JAVA_AWT_WM_NONREPARENTING=1` — correct window handling on wlroots
  compositors (Sway/Hyprland)
- `WEBKIT_DISABLE_DMABUF_RENDERER=1` — stable embedded browser (help/marketplace)
- `GTK_USE_PORTAL=0` — native GTK file dialogs

If native Wayland misbehaves on your compositor, force XWayland:

```sh
GDK_BACKEND=x11 stm32cubeide
```

## Notes

- Runs inside an FHS sandbox (`buildFHSEnv`); the bundled JRE/toolchain are not
  patchelf'd.
- First launch downloads MCU packs into `$HOME` (network needed at runtime).
- ST-Link/J-Link probes need udev rules on the host — add
  `hardware.stlink` or the ST/SEGGER udev rules to your NixOS config.

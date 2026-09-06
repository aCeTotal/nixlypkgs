{ python3, gamemode, writeScript, writeText, launchParams ? { } }:

# Per-game wrapper injected into every Steam app's LaunchOptions; applies PRIME
# offload, the per-GPU parameters from launchparams.nix, gamemoderun, and an
# adaptive performance tier (see TIERS below): every game starts on the
# fastest profile and is demoted automatically if it fails to stay up, so no
# game ever needs manual launch parameters. Its store path is baked into each
# entry, so autoconfig.nix re-patches on launch.
writeScript "nixly-game-wrap" ''
  #!${python3}/bin/python3
  """Wrap %command% with PRIME offload + adaptive perf tier + gamemoderun."""
  import json, os, shlex, signal, subprocess, sys, time

  GAMEMODERUN = "${gamemode}/bin/gamemoderun"

  # Kept in its own store file, since inlining JSON breaks on embedded quotes.
  with open("${writeText "nixly-launch-params.json"
      (builtins.toJSON launchParams)}") as _f:
      LAUNCH_PARAMS = json.load(_f)

  # Adaptive performance tiers, fastest first. Everything is applied with
  # setdefault, so Steam launch options and launchparams.nix always win.
  # Tier 0: low-latency dxvk (async compile threads, GPL auto, async off -
  #         the safe cachyos default), low-latency vkd3d, and on NVIDIA the
  #         Reflex layer (self-limiting: proton only injects it when the
  #         nvidia driver is loaded and the game asks for Reflex).
  # Tier 1: low-latency dxvk only.
  # Tier 2: plain proton-nixlyos (todays behavior).
  # Tier 3: hard-safe - additionally no low-latency Vulkan layer and no
  #         MangoHud fps cap, i.e. vanilla proton with zero extra layers.
  MAX_TIER = 3
  FAIL_SECS = 45        # exit before this = candidate crash
  PROVE_SECS = 600      # session past this = tier proven for this game
  DEMOTE_UNPROVEN = 2   # consecutive quick exits before demoting
  DEMOTE_PROVEN = 3     # a proven tier needs more evidence to demote

  def apply_tier(tier, vendor):
      if tier <= 1:
          os.environ.setdefault("PROTON_DXVK_LOWLATENCY", "1")
      if tier == 0:
          os.environ.setdefault("PROTON_VKD3D_LOWLATENCY", "1")
          if vendor == "nvidia":
              os.environ.setdefault("DXVK_NVAPI_VKREFLEX", "1")
      # The implicit low-latency layer (VK_AMD_anti_lag et al.) is safe as a
      # default (dedups against driver extensions, leaves native Reflex
      # alone), but tier 3 runs with no extra layers at all.
      os.environ.setdefault(
          "LOW_LATENCY_LAYER", "0" if tier >= MAX_TIER else "1")

  def default_tier(vendor):
      # Hardware preset: every recognized GPU (NVIDIA/AMD/Intel) starts on
      # the full low-latency profile; only unrecognized drivers start one
      # step down. Failures still demote from wherever a game starts.
      return 0 if vendor in ("nvidia", "amd", "intel") else 1

  def state_file():
      base = os.environ.get(
          "XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
      return os.path.join(base, "nixly-game-wrap", "tiers.json")

  def load_state():
      try:
          with open(state_file()) as f:
              return json.load(f)
      except (OSError, ValueError):
          return {}

  def save_state(state):
      path = state_file()
      try:
          os.makedirs(os.path.dirname(path), exist_ok=True)
          tmp = path + ".tmp"
          with open(tmp, "w") as f:
              json.dump(state, f, indent=1)
          os.replace(tmp, path)
      except OSError as e:
          print(f"[nixly-game-wrap] state save failed: {e}", file=sys.stderr)

  def build_id():
      # Compat tool store path changes with every proton-nixlyos release; a
      # new build resets every game to tier 0 so upgrades get re-probed.
      return os.path.basename(
          os.environ.get("STEAM_COMPAT_TOOL_PATHS", "").split(":")[0])

  def game_entry(state, appid):
      entry = state.get(appid)
      if not isinstance(entry, dict) or entry.get("build") != build_id():
          entry = {"tier": default_tier(gpu_vendor()), "streak": 0,
                   "proven": False, "build": build_id()}
          state[appid] = entry
      return entry

  def record_outcome(state, appid, duration, returncode):
      entry = game_entry(state, appid)
      if duration >= PROVE_SECS:
          entry.update(proven=True, streak=0)
      elif duration < FAIL_SECS:
          # Crash-style exits are stronger evidence than a quick quit.
          entry["streak"] += 2 if returncode not in (0, None) else 1
          needed = DEMOTE_PROVEN if entry["proven"] else DEMOTE_UNPROVEN
          if entry["streak"] >= needed and entry["tier"] < MAX_TIER:
              entry.update(tier=entry["tier"] + 1, streak=0, proven=False)
              print(f"[nixly-game-wrap] demoting {appid} to tier "
                    f"{entry['tier']}", file=sys.stderr)
      else:
          entry["streak"] = 0
      save_state(state)

  def drm_gpus():
      gpus = []
      try:
          for card in sorted(os.listdir("/sys/class/drm")):
              if not card.startswith("card") or "-" in card:
                  continue
              dev = f"/sys/class/drm/{card}/device"
              try:
                  with open(dev + "/vendor") as f:
                      vid = f.read().strip()
                  with open(dev + "/device") as f:
                      did = f.read().strip()
              except OSError:
                  continue
              boot = "0"
              try:
                  with open(dev + "/boot_vga") as f:
                      boot = f.read().strip()
              except OSError:
                  pass
              gpus.append({"vid": vid, "did": did, "boot": boot,
                           "slot": os.path.basename(os.path.realpath(dev))})
      except OSError:
          pass
      return gpus

  def apply_prime_offload():
      # Multiple GPUs: games ALWAYS run on the dGPU; the iGPU is only used
      # when it is the machine's sole GPU. Per-game only: forcing the Steam
      # UI itself onto the dGPU crashes CEF in a respawn loop, since
      # /run/opengl-driver is unbound inside the runtime.
      gpus = drm_gpus()
      if len(gpus) < 2:
          return
      if os.path.exists("/proc/driver/nvidia/version"):
          os.environ.setdefault("__NV_PRIME_RENDER_OFFLOAD", "1")
          os.environ.setdefault(
              "__NV_PRIME_RENDER_OFFLOAD_PROVIDER", "NVIDIA-G0")
          os.environ.setdefault("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
          os.environ.setdefault("__VK_LAYER_NV_optimus", "NVIDIA_only")
          dgpu = next((g for g in gpus if g["vid"] == "0x10de"), None)
      else:
          # dGPU = not the boot display, preferring non-Intel when mixed.
          cands = [g for g in gpus if g["boot"] != "1"] or gpus
          non_intel = [g for g in cands if g["vid"] != "0x8086"]
          dgpu = (non_intel or cands)[0]
          slot = dgpu["slot"].replace(":", "_").replace(".", "_")
          os.environ.setdefault("DRI_PRIME", f"pci-{slot}")
      if dgpu:
          # Force Vulkan onto the dGPU too (mesa device-select layer);
          # "!" pins it even if the app asks for another device.
          os.environ.setdefault(
              "MESA_VK_DEVICE_SELECT",
              f"{dgpu['vid'][2:]}:{dgpu['did'][2:]}!")

  def apply_ntsync():
      # Functional ntsync probe, not a file check: only a semaphore that actually
      # gets created yields "1", so Proton never picks a backend that dies later.
      if "PROTON_USE_NTSYNC" in os.environ:
          return
      ok = False
      try:
          import fcntl, struct
          fd = os.open("/dev/ntsync", os.O_RDWR)
          try:
              # Final 6.14+ ABI: create-sem returns the semaphore fd.
              try:
                  sem = fcntl.ioctl(
                      fd, 0x40084E80, bytearray(struct.pack("II", 0, 1)))
                  if isinstance(sem, int) and sem >= 0:
                      os.close(sem)
                      ok = True
              except OSError:
                  # Pre-6.14 RFC ABI writes the semaphore fd into args instead.
                  buf = bytearray(struct.pack("III", 0, 0, 1))
                  fcntl.ioctl(fd, 0xC00C4E80, buf)
                  sem = struct.unpack("III", bytes(buf))[0]
                  os.close(sem)
                  ok = True
          finally:
              os.close(fd)
      except OSError:
          ok = False
      os.environ["PROTON_USE_NTSYNC"] = "1" if ok else "0"

  def apply_fps_cap():
      # Cap fps through MangoHud's Vulkan layer (no_display, so nothing is
      # drawn). VRR output: refresh-4 keeps frametimes inside the VRR window;
      # hitting the top of the range falls back to vsync pacing (judder).
      # Fixed-Hz output: cap at exactly refresh, which stops render-queue
      # buildup without fighting vsync. The focused monitor is where
      # nixlytile puts the game; a MANGOHUD/MANGOHUD_CONFIG set by the user
      # (Steam launch options or launchparams.nix) always wins.
      if "MANGOHUD" in os.environ or "MANGOHUD_CONFIG" in os.environ:
          return
      sock_path = os.environ.get("NIRI_SOCKET")
      if not sock_path:
          return
      import socket
      try:
          s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
          s.settimeout(1.0)
          s.connect(sock_path)
          s.sendall(b'"Outputs"\n')
          data = b""
          while not data.endswith(b"\n"):
              chunk = s.recv(65536)
              if not chunk:
                  break
              data += chunk
          s.close()
          outputs = list(json.loads(data)["Ok"]["Outputs"].values())
      except (OSError, ValueError, KeyError, TypeError):
          return

      def refresh_mhz(o):
          try:
              return o["modes"][o["current_mode"]]["refresh_rate"]
          except (KeyError, IndexError, TypeError):
              return 0

      pick = next((o for o in outputs if o.get("focused")), None)
      if pick is None or refresh_mhz(pick) <= 0:
          pick = max(outputs, key=refresh_mhz, default=None)
      if pick is None:
          return
      hz = refresh_mhz(pick) // 1000
      if hz < 30:
          return
      cap = hz - 4 if pick.get("vrr_supported") else hz
      os.environ["MANGOHUD"] = "1"
      os.environ["MANGOHUD_CONFIG"] = f"no_display,fps_limit={cap}"

  def gpu_vendor():
      # The loaded driver picks the variant (nvidia > amd > intel when several
      # are present, matching what PRIME offload renders on).
      if os.path.exists("/proc/driver/nvidia/version"):
          return "nvidia"
      found = None
      try:
          for card in os.listdir("/sys/class/drm"):
              if not card.startswith("card") or "-" in card:
                  continue
              with open(f"/sys/class/drm/{card}/device/vendor") as f:
                  vid = f.read().strip()
              if vid == "0x1002":
                  return "amd"
              if vid == "0x8086":
                  found = "intel"
      except OSError:
          pass
      return found

  def apply_launch_params(cmd):
      # Leading KEY=VAL tokens become env vars; the rest are appended as args.
      # Applied after the adaptive tier and with direct assignment, so a
      # manual per-game entry always overrides the automatic choice.
      appid = os.environ.get("SteamAppId") \
          or os.environ.get("STEAM_COMPAT_APP_ID")
      vendor = gpu_vendor()
      if not appid or not vendor:
          return cmd
      spec = LAUNCH_PARAMS.get(f"{appid}_{vendor}")
      if not spec:
          return cmd
      args = []
      for tok in shlex.split(spec):
          key, sep, val = tok.partition("=")
          if not args and sep and key.isidentifier():
              os.environ[key] = val
          else:
              args.append(tok)
      return cmd + args

  def run_and_observe(cmd, state, appid):
      # Run the game as a child (not exec) so the session length and exit
      # code feed the tier state machine. Signals from Steam are forwarded;
      # if the wrapper itself is killed the state is simply left unchanged.
      start = time.monotonic()
      proc = subprocess.Popen(cmd)
      for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
          signal.signal(sig, lambda s, _f: proc.send_signal(s))
      rc = proc.wait()
      record_outcome(state, appid, time.monotonic() - start, rc)
      sys.exit(rc)

  def main():
      apply_prime_offload()
      apply_ntsync()

      appid = os.environ.get("SteamAppId") \
          or os.environ.get("STEAM_COMPAT_APP_ID")
      adaptive = os.environ.get("NIXLY_WRAP_ADAPTIVE", "1") != "0" and appid
      state = load_state()
      tier = 2
      if adaptive:
          entry = game_entry(state, appid)
          try:
              tier = int(os.environ.get("NIXLY_WRAP_TIER", entry["tier"]))
          except (ValueError, TypeError):
              tier = entry["tier"]
          tier = min(max(tier, 0), MAX_TIER)
      apply_tier(tier, gpu_vendor())

      cmd = [GAMEMODERUN, *apply_launch_params(sys.argv[1:])]
      # After apply_launch_params, so a per-game MANGOHUD_CONFIG wins.
      if tier < MAX_TIER:
          apply_fps_cap()

      if adaptive:
          try:
              run_and_observe(cmd, state, appid)
          except SystemExit:
              raise
          except Exception as e:
              # The observer must never keep a game from starting.
              print(f"[nixly-game-wrap] observer failed ({e}), exec fallback",
                    file=sys.stderr)
      os.execvp(cmd[0], cmd)

  if __name__ == "__main__":
      main()
''

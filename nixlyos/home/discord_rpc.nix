{ pkgs, ... }:

let
  # Discord Rich Presence: create an application at discord.com/developers,
  # paste its ID into clientId, and name an art asset or https image URL below.
  cfg = {
    clientId = ""; # <- Application ID from the developer portal (required)
    details = "NixlyOS"; # first text line
    state = "Hacking on nixlyos"; # second text line
    largeImage = ""; # asset name or https URL (big image)
    largeText = ""; # tooltip on big image
    smallImage = ""; # asset name or https URL (small corner image)
    smallText = ""; # tooltip on small image
    buttons = [ ]; # up to 2: [ { label = "GitHub"; url = "https://..."; } ]
  };

  configFile = pkgs.writeText "discord-rpc.json" (builtins.toJSON cfg);

  python = pkgs.python3.withPackages (ps: [ ps.pypresence ]);

  script = pkgs.writeText "discord-rpc.py" ''
    import glob
    import json
    import os
    import sys
    import time

    from pypresence import Presence

    with open("${configFile}") as f:
        cfg = json.load(f)

    if not cfg["clientId"]:
        print("discord-rpc: clientId not set in home/discord_rpc.nix; exiting.")
        sys.exit(0)

    def ipc_socket_exists():
        runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        dirs = [runtime, os.path.join(runtime, "app/com.discordapp.Discord"), "/tmp"]
        return any(glob.glob(os.path.join(d, "discord-ipc-*")) for d in dirs)

    def presence_kwargs(start):
        kwargs = {"start": start}
        for key, arg in [
            ("details", "details"),
            ("state", "state"),
            ("largeImage", "large_image"),
            ("largeText", "large_text"),
            ("smallImage", "small_image"),
            ("smallText", "small_text"),
        ]:
            if cfg[key]:
                kwargs[arg] = cfg[key]
        if cfg["buttons"]:
            kwargs["buttons"] = cfg["buttons"]
        return kwargs

    while True:
        if not ipc_socket_exists():
            time.sleep(5)
            continue
        try:
            rpc = Presence(cfg["clientId"])
            rpc.connect()
            start = int(time.time())
            print("discord-rpc: connected")
            while True:
                rpc.update(**presence_kwargs(start))
                time.sleep(15)
        except Exception as e:
            print(f"discord-rpc: disconnected ({e}); retrying")
            try:
                rpc.close()
            except Exception:
                pass
            time.sleep(5)
  '';
in
{
  systemd.user.services.discord-rpc = {
    Unit = {
      Description = "Discord Rich Presence daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${python}/bin/python ${script}";
      # on-failure, not always: an empty clientId exits cleanly and would
      # otherwise respawn forever.
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}

{ config, pkgs, lib, ... }:

let
  caveman-src = pkgs.fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "caveman";
    rev = "600e8efcd6aca4006051ca2a889aa8100a9b3967";
    hash = "sha256-gDPgQx1TIhGrJ2EVvEoDY+4MXdlI79zdcx6pL5nMEG4=";
  };
in
{
  home.packages = [ pkgs.nodejs ];

  home.file = {
    # Hook files — Node.js resolves symlinks so require('./caveman-config.js')
    # and path.join(__dirname, '..', 'skills', ...) work against the nix store
    ".claude/hooks/caveman-config.js".source = "${caveman-src}/hooks/caveman-config.js";
    ".claude/hooks/caveman-activate.js".source = "${caveman-src}/hooks/caveman-activate.js";
    ".claude/hooks/caveman-mode-tracker.js".source = "${caveman-src}/hooks/caveman-mode-tracker.js";
    ".claude/hooks/caveman-statusline.sh" = {
      source = "${caveman-src}/hooks/caveman-statusline.sh";
      executable = true;
    };

    # Slash commands
    ".claude/commands/caveman.toml".source = "${caveman-src}/commands/caveman.toml";
    ".claude/commands/caveman-commit.toml".source = "${caveman-src}/commands/caveman-commit.toml";
    ".claude/commands/caveman-review.toml".source = "${caveman-src}/commands/caveman-review.toml";
  };

  # Merge caveman hooks into ~/.claude/settings.json without clobbering existing config
  home.activation.setupCavemanHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SETTINGS="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"

    if [ ! -f "$SETTINGS" ]; then
      echo '{}' > "$SETTINGS"
    fi

    ${pkgs.nodejs}/bin/node - "$SETTINGS" << 'NODEOF'
const fs = require("fs");
const settingsPath = process.argv[2];

let settings = {};
try { settings = JSON.parse(fs.readFileSync(settingsPath, "utf8")); } catch {}

if (!settings.hooks) settings.hooks = {};
if (!Array.isArray(settings.hooks.SessionStart)) settings.hooks.SessionStart = [];
if (!Array.isArray(settings.hooks.UserPromptSubmit)) settings.hooks.UserPromptSubmit = [];

// Remove existing caveman hook entries (idempotent)
const notCaveman = (e) =>
  !(e.hooks && e.hooks.some((h) => h.command && h.command.includes("caveman")));

settings.hooks.SessionStart = settings.hooks.SessionStart.filter(notCaveman);
settings.hooks.UserPromptSubmit = settings.hooks.UserPromptSubmit.filter(notCaveman);

// Add caveman hooks
settings.hooks.SessionStart.push({
  hooks: [
    {
      type: "command",
      command: "node $HOME/.claude/hooks/caveman-activate.js",
      timeout: 5000,
    },
  ],
});

settings.hooks.UserPromptSubmit.push({
  hooks: [
    {
      type: "command",
      command: "node $HOME/.claude/hooks/caveman-mode-tracker.js",
      timeout: 5000,
    },
  ],
});

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
NODEOF
  '';
}

# Thumbnail cards for Claude's images.
{ pkgs, ... }:

let
  card = pkgs.writeShellApplication {
    name = "claude-thumb-card";
    runtimeInputs = with pkgs; [ libnotify swayimg ];
    text = ''
      action=$(notify-send --app-name=Claude --expire-time=8000 \
        --hint="string:image-path:$1" --action=default=Open --wait \
        "$(basename "$1")")
      if [ "$action" = default ]; then
        exec swayimg "$1"
      fi
    '';
  };

  # Viewer escapes the idle hook.
  hook = pkgs.writeShellApplication {
    name = "claude-thumb";
    runtimeInputs = with pkgs; [ jq util-linux ];
    text = ''
      f=$(jq -r '.tool_input.file_path // empty')
      case "''${f,,}" in
        *.png | *.jpg | *.jpeg | *.webp | *.gif | *.bmp) ;;
        *) exit 0 ;;
      esac
      if [ -f "$f" ]; then
        setsid -f chrt --other 0 ${card}/bin/claude-thumb-card "$f" >/dev/null 2>&1
      fi
    '';
  };
in
{
  environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
    hooks.PostToolUse = [
      {
        matcher = "Read";
        hooks = [
          {
            type = "command";
            command = "${hook}/bin/claude-thumb";
          }
        ];
      }
    ];
  };
}

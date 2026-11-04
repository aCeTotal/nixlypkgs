# FreeCAD med MCP-addon for Claude.
{ lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "desktop") {
  home-manager.sharedModules = [
    ({ pkgs, lib, ... }:
      let
        freecad = pkgs.freecad.customize {
          modules = [ "${pkgs.freecad-mcp}/share/freecad-mcp/FreeCADMCP" ];
        };
        server = builtins.toJSON {
          type = "stdio";
          command = lib.getExe pkgs.freecad-mcp;
          args = [ ];
        };
      in
      {
        home.packages = [ freecad pkgs.freecad-mcp ];

        # ~/.claude.json er muterbar; flett inn serveren.
        home.activation.claudeFreecadMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          f="$HOME/.claude.json"
          [ -s "$f" ] || echo '{}' > "$f"
          if ! ${lib.getExe pkgs.jq} -e --argjson s '${server}' '.mcpServers.freecad == $s' "$f" >/dev/null; then
            t=$(mktemp "$f.XXXXXX")
            ${lib.getExe pkgs.jq} --argjson s '${server}' '.mcpServers.freecad = $s' "$f" > "$t"
            mv "$t" "$f"
          fi
        '';
      })
  ];
}

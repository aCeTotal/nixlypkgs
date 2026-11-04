{ lib, python3Packages, fetchFromGitHub, freecad }:

python3Packages.buildPythonApplication rec {
  pname = "freecad-mcp";
  version = "0.1.28";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "neka-nat";
    repo = "freecad-mcp";
    tag = "v${version}";
    hash = "sha256-dryocwUb26S1+msUTZDUYGoyizxKuAeqMiTqyD8/ybo=";
  };

  # GUI side listens from launch.
  postPatch = ''
    substituteInPlace addon/FreeCADMCP/rpc_server/settings.py \
      --replace-fail '"auto_start_rpc": False' '"auto_start_rpc": True'
  '';

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    anyio
    certifi
    mcp
    pyjwt
    validators
  ];

  pythonRelaxDeps = [ "anyio" "certifi" "mcp" "pyjwt" ];

  makeWrapperArgs = [ "--add-flags" "--freecadcmd=${freecad}/bin/freecadcmd" ];

  postInstall = ''
    mkdir -p $out/share/freecad-mcp
    cp -r addon/FreeCADMCP $out/share/freecad-mcp/
  '';

  pythonImportsCheck = [ "freecad_mcp.server" ];

  meta = {
    description = "MCP server and FreeCAD addon for LLM-driven CAD";
    homepage = "https://github.com/neka-nat/freecad-mcp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "freecad-mcp";
  };
}

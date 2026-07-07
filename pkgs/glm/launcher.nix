# glm – starter lokal GLM-server (om nødvendig) og åpner ZCode.
{ writeShellApplication, curl, zcode, glm-server }:

writeShellApplication {
  name = "glm";
  runtimeInputs = [ curl ];
  text = ''
    PORT="''${GLM_PORT:-8484}"
    STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/glm"
    mkdir -p "$STATE_DIR"

    if ! curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      echo "Starter GLM-server (logg: $STATE_DIR/server.log)"
      nohup ${glm-server}/bin/glm-server >"$STATE_DIR/server.log" 2>&1 &
      echo "Venter på server ... (første kjøring laster ned modellen, følg loggen)"
      until curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; do
        sleep 2
      done
    fi

    echo "GLM-server klar: http://127.0.0.1:$PORT/v1 (modellnavn: glm-4.7-flash)"
    exec ${zcode}/bin/zcode "$@"
  '';
}

{ config, pkgs, lib, ... }:

# Local Ollama plus the `ai` chat TUI, with retrieval against the RAG server.
# The token in /etc/nixly-ai/token must match the server's; NIXLY_AI_MODEL and
# NIXLY_RAG_URL override the model and URL.

let
  ragUrl = "https://ai.aceclan.no";
  model = "qwen2.5-coder:7b-instruct";
  ollamaPort = 11434;

  cliPython = pkgs.python312.withPackages (ps: with ps; [
    httpx
    rich
    prompt-toolkit
  ]);

  # Versioned store path, so the wrapper below is a thin env bootstrap.
  cliScript = pkgs.runCommand "nixly-ai-cli" { } ''
    install -Dm0644 ${./cli.py} $out/share/nixly-ai/cli.py
  '';

  mkBin = name: pkgs.writeShellScriptBin name ''
    export NIXLY_RAG_URL="''${NIXLY_RAG_URL:-${ragUrl}}"
    export NIXLY_OLLAMA_URL="''${NIXLY_OLLAMA_URL:-http://127.0.0.1:${toString ollamaPort}}"
    export NIXLY_AI_MODEL="''${NIXLY_AI_MODEL:-${model}}"
    export PYTHONIOENCODING="''${PYTHONIOENCODING:-utf-8}"

    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet ollama.service; then
      ${pkgs.systemd}/bin/systemctl start ollama.service
    fi
    for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
      if ${pkgs.curl}/bin/curl -fsS -o /dev/null --max-time 1 \
          "http://127.0.0.1:${toString ollamaPort}/api/tags"; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.2
    done

    exec ${cliPython}/bin/python ${cliScript}/share/nixly-ai/cli.py "$@"
  '';
in
{
  # Local Ollama. CUDA primary, CPU offload for layers that don't fit.
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = ollamaPort;
    package = pkgs.ollama-cuda;
    loadModels = [ model ];
  };

  # Keep the model warm; single-stream throughput.
  systemd.services.ollama.environment = {
    OLLAMA_NUM_PARALLEL = "1";
    OLLAMA_MAX_LOADED_MODELS = "1";
    OLLAMA_KEEP_ALIVE = "24h";
    OLLAMA_FLASH_ATTENTION = "1";
    OLLAMA_KV_CACHE_TYPE = "q8_0";
  };

  systemd.services.ollama.serviceConfig = {
    CPUWeight = 200;
    Nice = -5;
  };

  # Directory only: the operator drops the token in, keeping it out of the store.
  systemd.tmpfiles.rules = [
    "d /etc/nixly-ai 0755 root root -"
  ];

  environment.systemPackages = [
    (mkBin "ai")
    (mkBin "nixly-ai")
  ];
}

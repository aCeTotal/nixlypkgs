{ config, lib, pkgs, nixlyUser, ... }:

let
  ollamaPort = 11434;
  idleSeconds = 600;

  idleStopScript = pkgs.writeShellScript "ollama-idle-stop" ''
    set -eu
    state_file=/run/ollama-idle-since

    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet ollama.service; then
      rm -f "$state_file"
      exit 0
    fi

    conn_count=$(${pkgs.iproute2}/bin/ss -tn "state established sport = :${toString ollamaPort}" 2>/dev/null \
      | ${pkgs.coreutils}/bin/tail -n +2 \
      | ${pkgs.coreutils}/bin/wc -l)

    now=$(${pkgs.coreutils}/bin/date +%s)

    if [ "$conn_count" -gt 0 ]; then
      rm -f "$state_file"
      exit 0
    fi

    if [ -f "$state_file" ]; then
      since=$(${pkgs.coreutils}/bin/cat "$state_file")
      age=$(( now - since ))
      if [ "$age" -ge ${toString idleSeconds} ]; then
        ${pkgs.systemd}/bin/systemctl stop ollama.service || true
        rm -f "$state_file"
      fi
    else
      echo "$now" > "$state_file"
    fi
  '';
in
# Gated on services.ollama.enable: ungated, the overrides generated an
# ollama.service with no ExecStart plus a timer polling a service that could
# never start. Import services/nixly-ai to enable it.
lib.mkIf config.services.ollama.enable {
  systemd.services.ollama.wantedBy = lib.mkForce [ ];

  systemd.services.ollama.environment = lib.mkForce {
    OLLAMA_NUM_PARALLEL = "1";
    OLLAMA_MAX_LOADED_MODELS = "1";
    OLLAMA_KEEP_ALIVE = "5m";
    OLLAMA_FLASH_ATTENTION = "1";
    OLLAMA_KV_CACHE_TYPE = "q8_0";
  };

  services.ollama.loadModels = lib.mkForce [ ];

  systemd.services.ollama-idle-stop = {
    description = "Stop ollama after ${toString idleSeconds}s of no client connections";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${idleStopScript}";
    };
  };

  systemd.timers.ollama-idle-stop = {
    description = "Periodic idle-stop check for ollama";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "60s";
      AccuracySec = "10s";
    };
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "${nixlyUser}") {
        var unit = action.lookup("unit");
        if (unit == "ollama.service") {
          return polkit.Result.YES;
        }
      }
    });
  '';
}

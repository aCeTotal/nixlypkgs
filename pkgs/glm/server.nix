# glm-server – llama.cpp server med automatisk GPU-deteksjon og modellvalg.
# Vulkan-backend: bruker automatisk NVIDIA/AMD/Intel-GPU uten unfree-avhengigheter.
{ lib, writeShellApplication, llama-cpp, curl, gawk, coreutils }:

let
  llama = llama-cpp.override { vulkanSupport = true; };
in
writeShellApplication {
  name = "glm-server";
  runtimeInputs = [ llama curl gawk coreutils ];
  text = ''
    MODELS_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/glm/models"
    PORT="''${GLM_PORT:-8484}"
    mkdir -p "$MODELS_DIR"

    # --- GPU-deteksjon: spør Vulkan-backend, foretrekk diskret GPU over iGPU ---
    mapfile -t devices < <(llama-server --list-devices 2>/dev/null | grep -E '^ +Vulkan[0-9]+:' || true)
    discrete=()
    for d in "''${devices[@]}"; do
      case "$d" in
        *NVIDIA*|*GeForce*|*RTX*|*Radeon*|*AMD*) discrete+=("$d") ;;
      esac
    done
    if [ "''${#discrete[@]}" -eq 0 ]; then discrete=("''${devices[@]}"); fi

    vram_mb=0
    dev_ids=""
    gpu_args=()
    for d in "''${discrete[@]}"; do
      dev_ids="$dev_ids,$(sed -E 's/^ +(Vulkan[0-9]+):.*/\1/' <<<"$d")"
      vram_mb=$(( vram_mb + $(sed -E 's/.*\(([0-9]+) MiB,.*/\1/' <<<"$d") ))
      echo "GPU: $(sed -E 's/^ +Vulkan[0-9]+: //' <<<"$d")"
    done
    dev_ids="''${dev_ids#,}"
    if [ -n "$dev_ids" ]; then
      gpu_args=(--device "$dev_ids")
    else
      echo "Ingen GPU funnet – kjører på CPU."
    fi

    ram_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
    total_gb=$(( (vram_mb + ram_mb) / 1024 ))

    # --- Velg beste kvantisering som får plass (VRAM+RAM) ---
    quant="''${GLM_QUANT:-auto}"
    if [ "$quant" = "auto" ]; then
      if   [ "$total_gb" -ge 48 ]; then quant="UD-Q6_K_XL"
      elif [ "$total_gb" -ge 30 ]; then quant="UD-Q4_K_XL"
      elif [ "$total_gb" -ge 20 ]; then quant="UD-Q3_K_XL"
      else                              quant="UD-IQ2_M"
      fi
    fi
    model="GLM-4.7-Flash-$quant.gguf"
    echo "Modell: $model"

    # --- Last ned ved første kjøring (kan gjenopptas) ---
    if [ ! -f "$MODELS_DIR/$model" ]; then
      echo "Laster ned $model fra Hugging Face ..."
      curl -L --fail -C - \
        -o "$MODELS_DIR/$model.part" \
        "https://huggingface.co/unsloth/GLM-4.7-Flash-GGUF/resolve/main/$model"
      mv "$MODELS_DIR/$model.part" "$MODELS_DIR/$model"
    fi

    # --- GPU-offload: full GPU hvis modellen får plass i VRAM, ellers MoE-eksperter på CPU ---
    model_mb=$(( $(stat -c%s "$MODELS_DIR/$model") / 1048576 ))
    moe_args=()
    if [ "$vram_mb" -lt $(( model_mb * 12 / 10 )) ]; then
      moe_args=(--cpu-moe)
      echo "Modell større enn VRAM: attention/KV på GPU, MoE-eksperter på CPU."
    fi

    exec llama-server \
      -m "$MODELS_DIR/$model" \
      -a glm-4.7-flash \
      --host 127.0.0.1 --port "$PORT" \
      -ngl 999 \
      --jinja \
      --ctx-size "''${GLM_CTX:-32768}" \
      "''${gpu_args[@]}" \
      "''${moe_args[@]}"
  '';
}

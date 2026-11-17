# Terminal output for nixlyos-update.
if [ -t 2 ]; then
  tty=1
  GRN=$'\033[32m' RED=$'\033[31m' YLW=$'\033[33m' CYN=$'\033[36m' DIM=$'\033[2m' BLD=$'\033[1m' RST=$'\033[0m'
else
  tty=0 GRN='' RED='' YLW='' CYN='' DIM='' BLD='' RST=''
fi
FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
BAR_WIDTH=28
MAX_SHOWN_BUILDS=3
REDRAW_US=80000
NAME_WIDTH=64

# Elapsed since $1, one decimal.
since() {
  local us=$(( ${EPOCHREALTIME/[.,]/} - $1 ))
  printf '%d.%ds' $(( us / 1000000 )) $(( us / 100000 % 10 ))
}

say() { (( tty )) && printf '%s\n' "$*" >&2 || :; }

step_done() { say "${GRN}✓${RST} $1${2:+ $DIM$2$RST}"; }

spin_pid=""
spin_start() {
  step_t=${EPOCHREALTIME/[.,]/}
  (( tty )) || return 0
  (
    trap 'exit 0' TERM
    i=0
    while :; do
      printf '\033[2K\r%s %s' "${CYN}${FRAMES:i%10:1}${RST}" "$1" >&2
      sleep 0.08
      i=$(( i + 1 ))
    done
  ) &
  spin_pid=$!
}

spin_stop() {
  [ -n "$spin_pid" ] || return 0
  kill "$spin_pid" 2>/dev/null || :
  wait "$spin_pid" 2>/dev/null || :
  spin_pid=""
  printf '\033[2K\r' >&2
}

tick() { spin_stop; step_done "$1" "$(since "$step_t")"; }

human_bytes() {
  local units=(B KiB MiB GiB TiB) tenths=$(( $1 * 10 )) i=0
  while (( tenths >= 10240 && i < 4 )); do tenths=$(( tenths / 1024 )) i=$(( i + 1 )); done
  printf '%d.%d %s' $(( tenths / 10 )) $(( tenths % 10 )) "${units[i]}"
}

store_name() { local n=${1##*/}; n=${n:33}; echo "${n%.drv}"; }

bar() {
  local fill=$(( $1 * BAR_WIDTH / ($2 > 0 ? $2 : 1) )) on off
  printf -v on '%*s' "$fill" ''
  printf -v off '%*s' $(( BAR_WIDTH - fill )) ''
  printf '%s%s%s%s%s' "$CYN" "${on// /━}" "$DIM" "${off// /━}" "$RST"
}

# Redraws the live block; render_progress owns the state.
frame() {
  local lines=() id n=0 done=$(( cd + bd )) total=$(( ce + be )) size=""
  local spin="${CYN}${FRAMES:fr:1}${RST}"
  if [[ $phase == eval ]]; then
    lines+=("$spin Evaluerer systemet ${DIM}$(since "$t0")${RST}")
  else
    (( bytes > 0 )) && size=" ${DIM}·${RST} $(human_bytes "$bytes")"
    lines+=("$spin $(bar "$done" "$total") ${BLD}$(printf '%3d' $(( done * 100 / (total > 0 ? total : 1) )))%${RST}  ${DIM}${done}/${total}${RST}${size}")
  fi
  for id in "${!active[@]}"; do
    (( n++ < MAX_SHOWN_BUILDS )) && lines+=("  ${DIM}bygger${RST} ${active[$id]:0:NAME_WIDTH}")
  done
  (( n > MAX_SHOWN_BUILDS )) && lines+=("  ${DIM}+ $(( n - MAX_SHOWN_BUILDS )) til${RST}")
  (( shown > 0 )) && printf '\033[%dA' "$shown" >&2
  printf '\033[2K%s\n' "${lines[@]}" >&2
  printf '\033[J' >&2
  shown=${#lines[@]}
}

clear_frame() {
  (( shown > 0 )) || return 0
  printf '\033[%dA\033[J' "$shown" >&2
  shown=0
}

transfer_summary() {
  local s=""
  (( $1 > 0 )) && s="$1 lastet ned" && (( $3 > 0 )) && s+=" ($(human_bytes "$3"))"
  (( $2 > 0 )) && s+="${s:+ · }$2 bygget"
  echo "$s"
}

# Consumes update-progress.jq events; failed drvs go to $1.
render_progress() {
  local failed_file=$1 t0 last=0 shown=0 fr=0 phase=eval
  local cd=0 ce=0 bd=0 be=0 bytes=0 ev a b c
  local -A active=()
  t0=${EPOCHREALTIME/[.,]/}
  : > "$failed_file"
  (( tty )) && printf '\033[?25l' >&2
  while :; do
    if IFS=$'\t' read -t 0.1 -r ev a b c; then
      case $ev in
        evaluated)
          (( tty )) && clear_frame
          step_done "Systemet evaluert" "$(since "$t0")"
          phase=build t0=${EPOCHREALTIME/[.,]/} ;;
        start) active[$a]=$(store_name "$b") ;;
        stop) unset "active[$a]" ;;
        count) if [[ $a == 103 ]]; then cd=$b ce=$c; else bd=$b be=$c; fi ;;
        bytes) bytes=$a ;;
        failed) echo "$a" >> "$failed_file" ;;
      esac
      (( tty )) || continue
      (( ${EPOCHREALTIME/[.,]/} - last < REDRAW_US )) && continue
    elif (( $? <= 128 )); then
      break
    fi
    (( tty )) || continue
    fr=$(( (fr + 1) % 10 )) last=${EPOCHREALTIME/[.,]/}
    frame
  done
  (( tty )) || return 0
  clear_frame
  printf '\033[?25h' >&2
  [[ $phase == build ]] && (( cd + bd > 0 )) &&
    step_done "$(transfer_summary "$cd" "$bd" "$bytes")" "$(since "$t0")"
  return 0
}

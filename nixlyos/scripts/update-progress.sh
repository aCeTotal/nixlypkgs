# Live view of nix builds.
RATE_WINDOW_US=1000000
MAX_SHOWN_BUILDS=3
ESTIMATE_CAP_PCT=99

# Reads sym, label, bar from caller.
bar_row() {
  printf -v row '  %s %-12s%s%*s  %s' "$sym" "$label" "$bar" "$TIME_WIDTH" "$1" "$2"
  lines+=("$row")
}

# Reads now, t0, est, spin from caller.
eval_row() {
  local t row bar sym=$spin label=Evaluerer elapsed=$(( now - t0 ))
  fmt_time t "$elapsed"
  if (( est == 0 )); then
    fmt_row row "Evaluerer systemet" "$t"
    lines+=("  $spin $row")
    return
  fi
  fmt_bar bar $(( elapsed < est ? elapsed : est * ESTIMATE_CAP_PCT / 100 )) "$est"
  bar_row "$t" ""
}

download_row() {
  local row bar sym=$spin label="Laster ned" size="" speed="" got=$dl total=$dlexp pct
  (( total )) || got=$sd total=$se
  pct=$(( got * 100 / total ))
  (( sd < se )) || sym="$GRN✓$RST"
  (( dlexp == 0 )) || fmt_pair size "$dl" "$dlexp"
  if (( sd < se && rate > 0 )); then
    fmt_bytes speed "$rate"
    speed="  $DIM$speed/s$RST"
  fi
  fmt_bar bar "$got" "$total"
  bar_row "$(( pct < 100 ? pct : 100 ))%" "$size$speed"
}

build_row() {
  local row bar sym=$spin label=Bygger
  (( bd < be )) || sym="$GRN✓$RST"
  fmt_bar bar "$bd" "$be"
  bar_row "$(( bd * 100 / be ))%" "$bd / $be pakker"
}

active_rows() {
  local id t row n=0
  for id in "${!active[@]}"; do
    (( ++n <= MAX_SHOWN_BUILDS )) || break
    fmt_time t $(( now - begun[id] ))
    fmt_row row "  ${active[id]:0:LABEL_WIDTH-4}" "$t"
    lines+=("    $DIM$row")
  done
  (( ${#active[@]} <= MAX_SHOWN_BUILDS )) ||
    lines+=("    $DIM  + $(( ${#active[@]} - MAX_SHOWN_BUILDS )) til$RST")
}

build_rows() {
  local t row
  if (( se + be == 0 )); then
    fmt_time t $(( now - t0 ))
    fmt_row row "Sjekker binærcache" "$t"
    lines+=("  $spin $row")
    return
  fi
  if (( se )); then download_row; fi
  if (( be )); then build_row; fi
}

# Smoothed bytes per second.
sample_rate() {
  (( now - rate_t >= RATE_WINDOW_US )) || return 0
  local r=$(( (dl - rate_dl) * 1000000 / (now - rate_t) ))
  rate=$(( rate ? (rate + r) / 2 : r ))
  rate_t=$now rate_dl=$dl
}

draw() {
  local lines=() spin="$CYN${FRAMES:fr:1}$RST" up="" body
  fr=$(( (fr + 1) % 10 )) last=$now
  sample_rate
  build_rows
  active_rows
  (( shown == 0 )) || printf -v up '\033[%dA' "$shown"
  printf -v body '\r%s\033[K\n' "${lines[@]}"
  printf '%s%s\033[J' "$up" "$body" >&2
  shown=${#lines[@]}
}

clear_frame() {
  (( shown )) || return 0
  printf '\033[%dA\r\033[J' "$shown" >&2
  shown=0
}

# Stamps download completion.
p_event() {
  dl=$1 dlexp=$2 sd=$3 se=$4 bd=$5 be=$6
  (( se == 0 || sd < se || sd_end )) || sd_end=$now
}

apply_event() {
  local name
  case $1 in
    p) p_event "${@:2}" ;;
    start) name=${3##*/} name=${name:33} active[$2]=${name%.drv} begun[$2]=$now ;;
    stop) unset "active[$2]" "begun[$2]" ;;
    failed) nfailed=$(( nfailed + 1 )) ;;
  esac
}

# Expected counts end one high.
summary() {
  local size=""
  if (( sd )); then
    (( dl == 0 )) || { fmt_bytes size "$dl"; size=" ($size)"; }
    step_done "Lastet ned $sd pakker$size" $(( ${sd_end:-$now} - t0 ))
  fi
  (( bd + nfailed )) || return 0
  if (( nfailed == 0 )); then step_done "Bygget $bd pakker" $(( now - t0 )); return; fi
  step_line "$RED✗$RST" "$nfailed av $(( bd + nfailed )) bygg feilet" $(( now - t0 ))
}

# $1 eval pid, $2 its start, $3 last eval time.
render_eval() {
  local now t0=$2 est=0 spin fr=0 lines
  (( tty )) || return 0
  [ ! -s "$3" ] || est=$(<"$3")
  printf '\033[?7l' >&2
  while kill -0 "$1" 2>/dev/null; do
    now=${EPOCHREALTIME/[.,]/} spin="$CYN${FRAMES:fr:1}$RST" lines=()
    fr=$(( (fr + 1) % 10 ))
    eval_row
    printf '\r%s\033[K' "${lines[0]}" >&2
    nap "$FRAME_S"
  done
  printf '\r\033[2K\033[?7h' >&2
}

# Live build view on stderr.
render_progress() {
  local shown=0 fr=0 last=0 status
  local now t0 rate_t dl=0 dlexp=0 sd=0 se=0 bd=0 be=0 rate=0 rate_dl=0 sd_end="" nfailed=0
  local -a ev=() active=() begun=()
  now=${EPOCHREALTIME/[.,]/} t0=$now rate_t=$now
  (( tty )) && printf '\033[?7l' >&2
  while :; do
    status=0
    IFS=$'\t' read -t "$FRAME_S" -r -a ev || status=$?
    (( status == 0 || status > 128 )) || break
    now=${EPOCHREALTIME/[.,]/}
    (( status )) || apply_event "${ev[@]}"
    (( tty == 0 || now - last < FRAME_US )) || draw
  done
  (( tty )) || return 0
  clear_frame
  printf '\033[?7h' >&2
  summary
}

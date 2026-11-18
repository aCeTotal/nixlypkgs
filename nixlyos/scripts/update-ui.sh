# Terminal output for nixlyos-update.
if [ -t 2 ]; then
  tty=1
  GRN=$'\033[32m' RED=$'\033[31m' YLW=$'\033[33m' CYN=$'\033[36m' DIM=$'\033[2m' BLD=$'\033[1m' RST=$'\033[0m'
else
  tty=0 GRN='' RED='' YLW='' CYN='' DIM='' BLD='' RST=''
fi
FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
FRAME_S=0.08
FRAME_US=80000
LABEL_WIDTH=36
TIME_WIDTH=8
BAR_WIDTH=$(( LABEL_WIDTH - 12 ))
UNITS=(B KiB MiB GiB TiB)

# Fork-free sleep.
exec {nap_fd}<> <(:)
nap() { read -rt "$1" -u "$nap_fd" || :; }

say() { (( tty )) && printf '%s\n' "$*" >&2 || :; }

# $1 = "4.2s" or "2m 05s".
fmt_time() {
  local s=$(( $2 / 1000000 ))
  if (( s < 60 )); then
    printf -v "$1" '%d.%ds' "$s" $(( $2 / 100000 % 10 ))
    return
  fi
  printf -v "$1" '%dm %02ds' $(( s / 60 )) $(( s % 60 ))
}

# $1 = "150.6 MiB".
fmt_bytes() {
  local tenths=$(( $2 * 10 )) i=0
  while (( tenths >= 10240 && i < 4 )); do tenths=$(( tenths / 1024 )) i=$(( i + 1 )); done
  printf -v "$1" '%d.%d %s' $(( tenths / 10 )) $(( tenths % 10 )) "${UNITS[i]}"
}

# $1 = "108.2 / 150.6 MiB".
fmt_pair() {
  local scale=1 i=0 d
  while (( $3 >= scale * 1024 && i < 4 )); do scale=$(( scale * 1024 )) i=$(( i + 1 )); done
  d=$(( $2 * 10 / scale ))
  printf -v "$1" '%d.%d / %d.%d %s' $(( d / 10 )) $(( d % 10 )) \
    $(( $3 * 10 / scale / 10 )) $(( $3 * 10 / scale % 10 )) "${UNITS[i]}"
}

# $1 = bar, half-cell steps.
fmt_bar() {
  local half=0 on off tip=""
  (( $3 > 0 )) && half=$(( $2 * BAR_WIDTH * 2 / $3 ))
  (( half <= BAR_WIDTH * 2 )) || half=$(( BAR_WIDTH * 2 ))
  (( half % 2 == 0 )) || tip=╸
  printf -v on '%*s' $(( half / 2 )) ''
  printf -v off '%*s' $(( BAR_WIDTH - half / 2 - ${#tip} )) ''
  printf -v "$1" '%s%s%s%s%s%s' "$CYN" "${on// /━}" "$tip" "$RST$DIM" "${off// /━}" "$RST"
}

# $1 = label, right-aligned time.
fmt_row() {
  local pad=$(( LABEL_WIDTH - ${#2} ))
  (( pad > 0 )) || pad=1
  printf -v "$1" '%s%*s%s%*s%s' "$2" "$pad" '' "$DIM" "$TIME_WIDTH" "$3" "$RST"
}

# Symbol, label, optional µs.
step_line() {
  local t="" row
  [ -z "${3:-}" ] || fmt_time t "$3"
  fmt_row row "$2" "$t"
  say "  $1 $row"
}

step_done() { step_line "$GRN✓$RST" "$@"; }

warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$1" >&2; }

# "✗ $1", stdin indented below.
error_block() {
  printf '  %s✗%s %s\n' "$RED" "$RST" "$1" >&2
  sed 's/^/    /' >&2
}

header() {
  (( tty )) || return 0
  printf '\033[?25l\n  %snixlyOS%s %soppdatering%s\n\n' "$BLD$CYN" "$RST" "$DIM" "$RST" >&2
}

# $1 µs total.
finished() {
  local t row
  fmt_time t "$1"
  fmt_row row "Oppdatering fullført" "$t"
  say ""
  say "  $GRN✓$RST $BLD$row"
}

spin_pid=""
spin_start() {
  step_t=${EPOCHREALTIME/[.,]/}
  (( tty )) || return 0
  (
    trap 'exit 0' TERM
    i=0
    while :; do
      fmt_time t $(( ${EPOCHREALTIME/[.,]/} - step_t ))
      fmt_row row "$1" "$t"
      printf '\r  %s %s\033[K' "$CYN${FRAMES:i:1}$RST" "$row" >&2
      i=$(( (i + 1) % 10 ))
      nap "$FRAME_S"
    done
  ) &
  spin_pid=$!
}

spin_stop() {
  [ -n "$spin_pid" ] || return 0
  kill "$spin_pid" 2>/dev/null || :
  wait "$spin_pid" 2>/dev/null || :
  spin_pid=""
  printf '\r\033[2K' >&2
}

tick() {
  spin_stop
  step_done "$1" $(( ${EPOCHREALTIME/[.,]/} - step_t ))
}

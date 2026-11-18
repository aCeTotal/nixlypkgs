# Nix internal-json to progress events.
@load "time"

BEGIN {
  FS = "\""  # Sorted keys: fixed positions.
  THROTTLE_S = 0.1
  ACT_TRANSFER = 101; ACT_COPY_PATHS = 103; ACT_BUILDS = 104; ACT_BUILD = 105
  RES_PROGRESS = 105; RES_SET_EXPECTED = 106
  dl = dlexp = sd = se = bd = be = 0
}

function num(s) { return substr(s, 2) + 0 }

function emit(s) { print s; fflush() }

function snapshot() { emit("p\t" dl "\t" dlexp "\t" sd "\t" se "\t" bd "\t" be) }

function throttled(   t) {
  t = gettimeofday()
  if (t - at < THROTTLE_S) return
  at = t
  snapshot()
}

function expected(   f) {
  split(substr($7, 3), f, ",")
  if (f[1] != ACT_TRANSFER) return
  dlexp = f[2] + 0
  snapshot()
}

function progress(   id, f) {
  id = num($9)
  if (!(id in kind)) return
  split(substr($7, 3), f, ",")
  if (kind[id] == ACT_TRANSFER) {
    dl += f[1] - xfer[id]
    xfer[id] = f[1]
    throttled()
    return
  }
  if (kind[id] == ACT_COPY_PATHS) { sd = f[1]; se = f[2] }
  if (kind[id] == ACT_BUILDS) { bd = f[1]; be = f[2] }
  snapshot()
}

function start(   t, id) {
  t = num($NF)
  id = substr($0, index($0, "\"id\":") + 5) + 0
  if (t == ACT_BUILD) { building[id] = 1; emit("start\t" id "\t" $8); return }
  if (t == ACT_TRANSFER || t == ACT_COPY_PATHS || t == ACT_BUILDS) { kind[id] = t; return }
  if (t == 0 && index($0, "\"text\":\"evaluating derivation")) evaluating = id
}

# Eval downloads are IFD.
function evaluated() {
  evaluating = 0
  dl = dlexp = 0
  delete xfer
  emit("evaluated")
}

function stop(   id) {
  id = num($7)
  if (evaluating && id == evaluating) { evaluated(); return }
  if (id in building) { delete building[id]; emit("stop\t" id); return }
  delete kind[id]
  delete xfer[id]
}

function failed(   m) {
  if (!match($0, /(Cannot build|builder for) '(\\u001b\[[0-9;]*m)?(\/nix\/store\/[^'\\]+\.drv)/, m)) return
  if (m[1] == "Cannot build" && $0 !~ /Reason: (\\u001b\[[0-9;]*m)?builder failed/) return
  emit("failed\t" m[3])
}

{ t = num($NF) }
$4 == "result" && t == RES_PROGRESS { progress(); next }
$4 == "result" && t == RES_SET_EXPECTED { expected(); next }
{ print > "/dev/stderr" }
$4 == "start" { start() }
$4 == "stop" { stop() }
$4 == "msg" && index($0, "\"level\":0,") { failed() }
